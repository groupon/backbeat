#!/bin/bash

rake db:reset
rake db:migrate
bundle exec rspec
V2=true bundle exec rspec
