#!/bin/bash

rake db:reset
rake db:migrate
V2=true bundle exec rspec
