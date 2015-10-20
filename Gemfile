source ENV.fetch('GEM_SOURCE', 'https://rubygems.org/')

gem 'rake'

gem 'grape', '~> 0.11.0'
gem 'puma', '~> 2.13.4'
gem 'httparty'

group :torquebox do
  platform :jruby do
    gem 'jruby-openssl', :require => false
    gem 'torquebox', '3.0.0'
    gem 'torquebox-messaging', '3.0.0'
    gem 'warbler'
    gem 'torquebox-server'
  end
end

gem 'activerecord', '~> 4.1.0', require: 'active_record'
platform :jruby do
  gem 'activerecord-jdbcpostgresql-adapter'
  gem 'jdbc-postgres'
end
platform :mri do
  gem 'activerecord-postgresql-adapter'
end
gem 'foreigner'
gem 'enumerize'

gem 'awesome_print'
gem 'mail'
gem 'sidekiq', '~> 3.5.0'
gem 'sidekiq-failures', '~> 0.4.0'
gem 'sinatra', require: false # for the Sidekiq UI

group :development, :test do
  gem 'pry'
end

group :test do
  gem 'database_cleaner'
  gem 'rack-test'
  gem 'rspec', '~> 3.2.0'
  gem 'rspec-sidekiq'
  gem 'factory_girl'
  gem 'timecop'
  gem 'webmock'
  gem 'zip'
end
