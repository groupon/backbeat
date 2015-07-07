#!/bin/bash

bundle exec rake db:migrate
bin/add_user

webserver=$1

if [[ -n "$webserver" ]]; then
  bundle exec $webserver
else
  bundle exec rackup
fi
