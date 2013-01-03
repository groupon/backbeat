#!/bin/bash

bundle exec rake db:reset
bundle exec rake db:migrate
bundle exec rspec
