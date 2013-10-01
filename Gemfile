source 'http://rubygems.org'

gem 'rake'
ruby '1.9.3'

# Server/API
gem 'grape'
gem 'httparty'
gem 'log4r'

# Database
gem 'mongoid', git: 'http://github.com/mongoid/mongoid.git', branch: '3.1.0-stable'
gem 'mongoid-locker', git: 'git://github.com/mooremo/mongoid-locker.git'
gem 'delayed_job_mongoid'
gem 'mongoid_auto_increment'
gem 'mongoid-indifferent-access'
gem 'uuidtools'

# Utility
gem 'awesome_print'
gem 'mail'
gem 'sidekiq'
gem 'kiqstand'

gem 'service-discovery', git: 'git@github.groupondev.com:groupon-api/service-discovery.git'
gem 'squash_ruby', :require => 'squash/ruby'
gem 'newrelic_rpm'
gem 'jruby-openssl', require: false

#Torquebox
gem 'torquebox', '3.0.0'
gem 'torquebox-messaging', '3.0.0'
gem 'warbler'

group :development do
  # Documentation
  gem 'rdoc', '~> 3.4'
  gem 'torquebox-console'
  gem 'torquebox-capistrano-support'
end

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'rspec-sidekiq'
  gem 'factory_girl'
  gem 'timecop'
  gem 'webmock'
  gem 'simplecov'
  gem 'torquebox-console'
  gem 'torquespec', require: false
  gem 'accounting_torquespec', git: 'git@github.groupondev.com:finance-engineering/accounting_torquespec.git'
  gem 'external_service', git: 'git@github.groupondev.com:finance-engineering/external_service.git'
  gem 'torquebox-capistrano-support'
  gem 'zip'
  gem 'pry'
end
