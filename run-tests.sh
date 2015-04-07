#!/bin/bash

EXIT=0
rake db:reset
rake db:migrate
V2=true bundle exec rspec
EXIT+=$?
bundle exec rspec
EXIT+=$?

exit $EXIT
