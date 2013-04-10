source 'http://rubygems.org'
ruby '1.9.3'

gem 'rake'

# Server/API
gem 'unicorn', platform: :ruby
gem 'puma',    platform: :jruby
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

gem 'service-discovery', git: 'git@github.groupondev.com:groupon-api/service-discovery.git'

group :development do
  # Deploy
  gem 'capistrano'
  gem 'capistrano-ext'
  gem 'capistrano-campfire'
  # Documentation
  gem 'rdoc'
end

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'factory_girl'
  gem 'pry'
  gem 'timecop'
  gem 'webmock'
  gem 'simplecov'
end
