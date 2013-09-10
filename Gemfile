source 'http://rubygems.org'

gem 'rake'

# Server/API
gem 'grape'
gem 'httparty'
gem 'log4r'

# Database
gem 'mongoid'
gem 'mongoid-locker', git: 'git://github.com/mooremo/mongoid-locker.git'
gem 'delayed_job_mongoid'
gem 'mongoid_auto_increment'
gem 'mongoid-indifferent-access'
gem 'uuidtools'

# Utility
gem 'awesome_print'
gem 'mail'
gem 'rufus-scheduler'
gem 'whenever'
gem 'resque'

gem 'service-discovery', git: 'git@github.groupondev.com:groupon-api/service-discovery.git'
gem 'squash_ruby', :require => 'squash/ruby'
gem 'newrelic_rpm'
gem 'jruby-openssl', require: false

#Torquebox
gem 'torquebox'
gem 'torquebox-messaging'

group :development do
  # Deploy
  gem 'capistrano'
  gem 'capistrano-ext'
  gem 'capistrano-campfire'
  # Documentation
  gem 'rdoc', '~> 3.4'
  gem 'torquebox-console'
end

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'factory_girl'
  gem 'pry'
  gem 'timecop'
  gem 'webmock'
  gem 'simplecov'
  gem 'torquebox-console'
  gem 'torquespec', require: false
end
