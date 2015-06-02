#!/bin/bash

bundle exec rake db:migrate
bin/add_user
rackup config.ru
