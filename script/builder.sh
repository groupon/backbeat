#!/bin/bash

ruby_version=ruby-1.9.3-p194
branch=master
export CORES=21
setup_log=log/setup.log

# parse out the options
# the b:c:r:... tell getops what the argument names are (b: means b takes a value)
while getopts b:c:dgn:p:r:s: opt
do	case "$opt" in
	b)  branch="$OPTARG";;
	c)  export CORES="$OPTARG";;
  d)  rebuild_db=true;;
  g)  rebuild_gemset=true;;
	n)	build_name="$OPTARG";;
  p)  post_build_script="$OPTARG";;
	r)	ruby_version="$OPTARG";;
	s)  setup_log="$OPTARG";;
	[?])	echo "Usage: $0 -n build_name [-d (reset the db)] [-b branch] [-p post_build_script] [-r ruby_version] build_command..."
		exit 1;;
	esac
done
shift $((OPTIND-1))

echo "Preparing build" # for collapsing sections
echo "Writing preparation to $setup_log"
echo "Building branch: ${branch}"

source "$HOME/.rvm/scripts/rvm"
#rvm use "$ruby_version@groupon-$build_name" --create
rvm use "$ruby_version@groupon-workflow" --create

if [ $rebuild_gemset ]; then
  echo "Emptying gemset"
  echo yes | rvm gemset empty
fi

# fast ree settings
## these don't matter in ruby 1.9.2
#export RUBY_GC_MALLOC_LIMIT=50000000
#export RUBY_HEAP_MIN_SLOTS=500000
#export RUBY_HEAP_SLOTS_GROWTH_FACTOR=1
#export RUBY_HEAP_SLOTS_INCREMENT=250000

rm -fr log/* .git/rebase-apply
#cp config/database.yml.example config/database.yml

#gem install --no-ri --no-rdoc rake --version=0.8.7 > $setup_log
gem install --no-ri --no-rdoc bundler >> $setup_log
# the first commands are for building mysql, second for ffi
echo "Installing gems via bundler"
#(CONFIGURE_ARGS="--with-ldflags='-Xlinker -R/usr/local/lib/mysql'" make="make CFLAGS='-fPIC -D__USE_XOPEN2K8'" bundle install --without=development >> $setup_log) || exit 1
echo "YES" | bundle install

export DATABASE_SUFFIX="_$build_name"
#bundle exec rake db:create:all >> $setup_log

#if [ $rebuild_db ]; then
#  echo "Rebuilding the db"
#  (bundle exec rake db:migrate:reset >> $setup_log) || exit 1
#fi

echo "Finished preparing build" # for collapsing sections
echo "Executing build with $@" # for collapsing sections

$@
exit_code=$?

echo "Build returned $exit_code"

if [ $exit_code -eq 0 ]; then
  # Run the post_build_script if it's set and the file is a file
  if [ $post_build_script ] && [ -f $post_build_script ]; then
    echo "Running post build hooks since the build passed"

    echo "Running $post_build_script ${branch}"
    $post_build_script ${branch}

    exit_code=$?
  fi
else
  if [ $post_build_script ]; then
    echo "Skipping post build hooks since the build failed"
  fi
fi

gzip log/test.log

exit $exit_code
