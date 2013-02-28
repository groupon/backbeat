# -*- encoding : utf-8 -*-
require 'bundler/capistrano'
require "#{File.dirname(__FILE__)}/useful_capistrano_functions"

set :stages, %w(production staging uat)
set :default_stage, "uat"
require 'capistrano/ext/multistage'  # this must appear after you set up the stages


require 'bundler/capistrano'
require "#{File.dirname(__FILE__)}/useful_capistrano_functions"

require 'capistrano/campfire'

#set :newrelic_rails_env, defer { stage }
#require 'new_relic/recipes'

set :whenever_roles, :cronjobs
set :whenever_command, "bundle exec whenever"
set :whenever_environment, defer { stage }
require 'whenever/capistrano'

# campfire options came from groupon/capistrano/config/notification_helper.yml
set :campfire_options, { :account => 'thepoint',
                         :room => 'Accounting-fu',
                         :token => 'efb2f09a510a1cbda365a1c228ab8613a769930f',
                         :ssl_verify => OpenSSL::SSL::VERIFY_NONE, # sigh
                         :ssl => true }

set :application, "backbeat"
set :repository,  'git@github.groupondev.com:finance-engineering/backbeat.git'
set :scm, :git
set :user, :backbeat
set :group, :backbeat
set :use_sudo, false
set :deploy_via, :remote_cache
set :deploy_to, "/var/groupon/#{application}"
set :deploy_env, "production"
set :keep_releases, 10
set :normalize_asset_timestamps, false
# QUICK TIP (useful for debugging) - If bundle is failing, uncomment the line below. It executes bundle without the quiet flag.
#set :bundle_flags, "--deployment"

set :unicorn_binary, "bundle exec unicorn"
set :unicorn_config, "#{current_path}/config/unicorn.conf.rb"
set :unicorn_pid, "#{deploy_to}/shared/pids/unicorn.pid"
set :worker_init_scripts, [:delayed_job]

ssh_options[:forward_agent] = true

def campfire_speak msg
  begin
    #puts "Deploying #{msg}"
    campfire_room.speak msg
  rescue => err
    puts "unable to speak: #{msg}"
    puts err.inspect
    puts err.backtrace
  end
end

Capistrano::Configuration::Namespaces::Namespace.class_eval do
  def capture(*args)
    parent.capture *args
  end
end

# Only used by Release Engineering for production deploys
namespace :git do
  desc "tag the deployed revision as a deploy"
  task :tag_deploy do
    @deploy_day = `date +"%Y-%m-%d"`.strip
    @deploy_timestamp = `date +"%Y-%m-%d_%H.%M"`.strip
    @deploy_tag_prefix = "production_deploy_"
    @deploy_sha = real_revision
    @deploy_repo = "git@github.groupondev.com:release-engineering/production-deploy-population.git"
    @deploy_repo_dir = "production-deploy-population"
    @tmp_dir = "~/tmp"
    @tmp_deploy_repo_dir = "#{@tmp_dir}/#{@deploy_repo_dir}"
    @app_dir_in_deploy_repo = get_app_dir_name
    @sox_artifact = "#{@deploy_timestamp}:#{@deploy_sha}"
    @deploy_tag_day = @deploy_tag_prefix + "#{@app_dir_in_deploy_repo}_" + @deploy_day
    @deploy_tag =  @deploy_tag_prefix + "#{@app_dir_in_deploy_repo}_" + @deploy_timestamp

    setup_and_go_to_deploy_repo
    commit_and_push_sox_artifact unless deploy_already_tagged?
  end

  def get_app_dir_name
    app_dir = "#{repository.split(':').last.gsub('.git','')}"
    if app_dir.include?("/")
      app_dir = app_dir.split("/").last
    end
    app_dir
  end

  def setup_and_go_to_deploy_repo
    remove_tmp_deploy_repo
    `mkdir -p #{@tmp_dir} && cd #{@tmp_dir} && git clone #{@deploy_repo} && cd #{@deploy_repo_dir} && mkdir -p #{@app_dir_in_deploy_repo}`  
  end

  def commit_and_push_sox_artifact
    create_sox_artifact
    commit_and_push
    set_and_push_deploy_tag 
    remove_tmp_deploy_repo
  end

  def create_sox_artifact
    `cd #{@tmp_deploy_repo_dir} && echo '#{@sox_artifact}' > #{@app_dir_in_deploy_repo}/#{@deploy_timestamp}.txt`
  end

  def commit_and_push
    `cd #{@tmp_deploy_repo_dir} && git add . && git commit -m "Logging deploy for application:#{@app_dir_in_deploy_repo} revision:#{@deploy_sha}" && git pull --rebase && git push origin master`
  end

  def set_and_push_deploy_tag
    `cd #{@tmp_deploy_repo_dir} && git fetch origin && git fetch --tags && git tag #{@deploy_tag} HEAD && git push --tags`
  end

  def deploy_already_tagged?
    deploy_tags_from_today = find_deploy_tags_from_today
    return false if deploy_tags_from_today.empty?
    deployed_revisions = find_deployed_revisions
    deployed_revisions.include?(@deploy_sha)
  end

  def find_deploy_tags_from_today
    `cd #{@tmp_deploy_repo_dir} && git ls-remote #{@deploy_repo} refs/tags/#{@deploy_tag_day}* | awk '{print $1}'`.split("\n")
  end

  def find_deployed_revisions
    `cd #{@tmp_deploy_repo_dir} && git fetch --tags && git tag | grep #{@deploy_tag_day} | xargs -ITAG git log -n 1 $TAG | grep "Logging deploy for" | grep #{@app_dir_in_deploy_repo} | awk -F 'revision:' '{print $2}'`.split("\n")
  end

  def remove_tmp_deploy_repo
    `rm -rf #{@tmp_deploy_repo_dir}`
  end
end

namespace :setup do
  desc "configure deploy directories"
  task :deploy_dirs, :roles => :utility do
    set :user, ENV['DEPLOYER'] || ENV['USER']
    sudo "mkdir -p #{deploy_to}/releases; sudo chown -R backbeat:backbeat #{deploy_to}"
  end
end

namespace :roller do
  desc "build a new roller package.  pass PACKAGE=<package_name> on cl"
  task :build_package do
    set :user, ENV['DEPLOYER'] || ENV['USER']

    package_name = ENV['PACKAGE']
    local_package_location = "config/roller/#{package_name}/"

    if package_name.nil? || package_name.empty?
      puts "Please specify PACKAGE=package_name on command line"
      exit 1
    elsif !Dir.exists?(local_package_location)
      puts "Can't find #{package_name} under config/roller"
      exit 2
    end

    date_ext = Time.now.strftime("%Y.%m.%d_%H.%M")
    dirname = "#{package_name}-#{date_ext}"
    filename = "#{dirname}.tar.gz"
    system("rsync -a #{local_package_location} /tmp/#{dirname}; cd /tmp; gnutar zcf #{filename} #{dirname}")

    upload( "/tmp/#{filename}", "./#{filename}", :hosts => ["dev1.snc1"] )
    run( "publish_encap #{filename}", :hosts => ["dev1.snc1"] )
    puts "created roller package named: #{dirname}"
  end
end

namespace :workers do
  [:start, :stop, :restart, :status].each do |command|
    desc "#{command} worker processes on utility box"
    task command, :roles => [:delayed_job] do
      worker_init_scripts.each do |script|
        run "/usr/local/etc/init.d/#{script}_#{application} #{command}"
      end
    end
  end
end

namespace :deploy do

  # Deploy locks courtesy of http://kpumuk.info/development/advanced-capistrano-usage/
  desc "Prevent other people from deploying to this environment"
  task :lock do
    check_lock
    msg = ENV['MESSAGE'] || ENV['MSG'] ||
          fetch(:lock_message, 'Default lock message. Use MSG=msg to customize it')
    campfire_speak "#{ENV['USER']} locked #{stage}"
    case stage
    when :uat
      campfire_speak 'http://i.imgur.com/p9yQS.jpg'
    when :staging
      campfire_speak 'http://i.imgur.com/Pi1g0.jpg'
    end
    timestamp = Time.now.strftime("%m/%d/%Y %H:%M:%S %Z")
    lock_message = "Deploys locked by #{ENV['USER']} at #{timestamp}: #{msg}"
    put lock_message, "#{shared_path}/system/lock.txt", :mode => 0644
  end

  desc "Check if deploys are OK here or if someone has locked down deploys"
  task :check_lock do
    # We use echo in the end to reset exit code when lock file is missing
    # (without it deployment will fail on this command — not exactly what we expected)
    data = capture("cat #{shared_path}/system/lock.txt 2>/dev/null;echo").to_s.strip

    if data != '' and !(data =~ /^Deploys locked by #{ENV['USER']}/)
      logger.info "\e[0;31;1mATTENTION:\e[0m #{data}"
      if ENV['FORCE']
        logger.info "\e[0;33;1mWARNING:\e[0m You have forced the deploy"
      else
        abort 'Deploys are locked on this machine'
      end
    end
  end

  desc "Remove the deploy lock"
  task :unlock do
    run "rm -f #{shared_path}/system/lock.txt"
    campfire_speak "#{ENV['USER']} unlocked #{stage}"
    case stage
    when :uat
      campfire_speak 'http://i.imgur.com/oBHBz.jpg'
    when :staging
      campfire_speak 'http://i.imgur.com/Wx6O4.jpg'
    end
  end

  namespace :rollback do
    desc "we overwrote cleanup because it was screwing up unicorn which couldn't find its files during restart"
    task :cleanup do
      puts Color.red("Please note.  The rollbacked version of the code (#{current_release}) is still on the server.  You should move it out of the way once unicorn has restarted with the rolled back code.")
    end
  end

  desc "start unicorn"
  task :start, :roles => :utility do
    run "cd #{current_path} && RACK_ENV=#{stage} #{unicorn_binary} -c #{unicorn_config} -D"
  end

  desc "stop unicorn"
  task :stop, :roles => :utility do
    run "kill -s KILL `cat #{unicorn_pid}` || true"
  end

  desc "rereads unicorn config files"
  task :reread_config, :roles => :utility do
    run "kill -s HUP `cat #{unicorn_pid}` || true"
  end

  desc "gracefully stop unicorn"
  task :graceful_stop, :roles => :utility do
    run "kill -s QUIT `cat #{unicorn_pid}` || true"
  end

  desc "gracefully stop/start unicorn (execs new unicorn instance, old one times out)"
  task :restart, :roles => :utility do
    roles[:utility].instance_variable_get('@static_servers').each do |host|
      if unicorn_pids_by_host[host].empty?
        run "(cd #{current_path} && RACK_ENV=#{stage} #{unicorn_binary} -c #{unicorn_config} -D)"
      else
        run "kill -s USR2 `cat #{unicorn_pid}`"
      end
    end
  end

  task :create_indexes, :roles => :utility do
    run "(cd #{current_path} && RACK_ENV=#{stage} bundle exec rake mongo:create_indexes)"
  end

  task :remove_indexes, :roles => :utility do
    run "(cd #{current_path} && RACK_ENV=#{stage} bundle exec rake mongo:remove_indexes)"
  end

  desc "rolling killing/restarting of unicorn. use this if unicorn gets in a weird state"
  task :rolling_restart, :roles => :utility do
    roles[:utility].instance_variable_get('@static_servers').each do |host|
      run "kill -9 `cat #{unicorn_pid}` || true", :hosts => host
      # 30 is the timeout for any unicorn request. we should be able to restart within 30 seconds. 35 just to be safe
      run "for i in {1..35}; do if nc -z localhost 9000;then sleep 1; else break; fi done", :hosts => host
      run "`cd #{current_path} && RACK_ENV=#{stage} #{unicorn_binary} -c #{unicorn_config} -D`", :hosts => host
    end
  end

  desc "shows the differences between what's about to deploy vs what's currently deployed"
  task :show_diffs, :roles => :utility do
    current_revision = capture( "cat #{current_path}/REVISION" )
    deploy_branch = exists?(:branch) ? branch : 'master'
    about_to_deploy_revision = sha_from_branch(deploy_branch)
    puts "git diff #{current_revision.chomp} #{about_to_deploy_revision.chomp}"
    system "git diff #{current_revision.chomp} #{about_to_deploy_revision.chomp}"
  end

  # desc "copies correct settings file into place"
  # task :copy_settings, :roles => [:app, :db, :utility] do
  #   run "rsync -av #{release_path}/config/#{stage}/settings.yml #{release_path}/config/settings.yml"
  # end

  desc "let campfire room know about deploy"
  task :campfire_notify do
    deploy_branch = exists?(:branch) ? branch : 'master'
    campfire_speak "Backbeat is marching to #{stage}!\n#{ENV['USER']} started deploying branch(#{deploy_branch}) SHA(#{sha_from_branch(deploy_branch)})"
    memes = []
    case stage
    when :uat
      memes = []
    when :staging
      memes = []
    when :production
      if Time.now.hour >= 15
        memes = []
      else
        memes = []
      end
    end

    campfire_speak memes[rand(memes.size)] unless memes.empty?
  end

  desc "let campfire room know about deploy completion"
  task :campfire_notify_complete do
    deploy_branch = exists?(:branch) ? branch : 'master'
    campfire_speak "#{ENV['USER']} finished deploying branch(#{deploy_branch}) to #{stage}"
  end

  task :find_existing_unicorn_processes, :roles => :utility do
    unless exists?(:unicorn_pids_by_host)
      set :unicorn_pids_by_host, Hash.new {|h,k| h[k] = [] }
    end
    roles[:utility].instance_variable_get('@static_servers').each do |host|
      puts "HOST: #{host}"
      pids = capture("ps -A -o pid,args | grep unicorn | grep -v grep | awk '{print $1}'", :hosts => host )
      unicorn_pids_by_host[host] = pids.split(/\n/)
    end
  end

  task :check_for_new_unicorn_processes, :roles => :utility do
    unless exists?(:unicorn_pids_by_host)
      puts Color.red("WARNING: You are checking for new unicorn processes but find_existing_unicorn_processes never ran.  I will now explode.")
    end

    new_unicorn_pids_by_host = Hash.new {|h,k| h[k] = [] }

    roles[:utility].instance_variable_get('@static_servers').each do |host|
      puts "HOST: #{host}"
      pids = capture("ps -A -o pid,args | grep unicorn | grep -v grep | awk '{print $1}'", :hosts => host )
      new_unicorn_pids_by_host[host] = pids.split(/\n/)
    end

    puts "Old #{unicorn_pids_by_host}"
    puts "New #{new_unicorn_pids_by_host}"

    unicorn_pids_by_host.each_pair do |host,pids|
      new_pids = new_unicorn_pids_by_host[host] - pids
      if new_pids.size == 0
        puts Color.red("WARNING: No New Unicorn processes on #{host}, only the old ones: #{pids.inspect}.  Killing/restarting the brutally unicorn the hard way.")
        run "kill -9 `cat #{unicorn_pid}` || true", :hosts => host
        run "`cd #{current_path} && RACK_ENV=#{stage} #{unicorn_binary} -c #{unicorn_config} -D`", :hosts => host
      else
        puts Color.green("Woo hoo.  New unicorn processes are spinning up: #{new_pids.join(",")}")
      end
    end
  end

  desc "show runtime of unicorn processes"
  task :check_processes, :roles => :utility do
    puts "pid,uptime,process name"
    run "echo pid, uptime, process name; ps -A -o pid,etime,args | grep unicorn | grep -v grep | awk '{print $1 \" \" $2 \" \" $3 \" \" $4}'"
  end

  task :confirm do
    if stage == :production
      Groupon::FinancialEngineering::Capistrano.get_confirmation( "let's march!", "deploy to production")
    else
      puts "skipping confirmation, you are deploying to #{stage}"
    end
  end
end

def sha_from_branch(arg)
  branch_to_sha = {}
  `git ls-remote`.split("\n").each do |line|
    sha, branch = line.split("\t")
    branch = 'master' if branch == 'HEAD'
    branch.gsub!(/^refs\/heads\//, '')
    branch_to_sha[branch] = sha
  end
  branch_to_sha[arg]
end

before :deploy do
  deploy.check_lock
end

before "deploy:update_code", "deploy:confirm", "deploy:campfire_notify", "workers:stop"
#after "deploy:update_code"#, "deploy:copy_settings"

before "deploy:restart", "deploy:find_existing_unicorn_processes"
after "deploy:restart", "deploy:check_for_new_unicorn_processes", "deploy:create_indexes", "deploy:cleanup"
after "deploy:cleanup", "deploy:check_processes", "workers:start", "deploy:campfire_notify_complete"

#after "deploy:create_symlink", "newrelic:notice_deployment"
