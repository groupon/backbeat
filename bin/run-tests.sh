#!/bin/bash

rake db:reset
rake db:migrate
bundle exec rspec
