ENV['RACK_ENV'] ||= 'test'

require File.expand_path('../../config/environment',  __FILE__)

$: << File.expand_path('../', __FILE__)

require 'bundler'
Bundler.setup(:test)

require 'rspec'
require 'rack/test'
require 'factory_girl'
require 'database_cleaner'
require 'timecop'
require 'webmock'
require 'rspec-sidekiq'
require 'pry'
require 'securerandom'

unless ENV['CONSOLE_LOG']
  log_dir = File.expand_path("../../log", __FILE__)
  Dir.mkdir(log_dir) unless File.exist?(log_dir)
  Backbeat::Logger.set_logger(Logger.new(File.open("#{log_dir}/test.log", "a+")))
end

RACK_ROOT = File.expand_path(File.join(__FILE__,'..'))
ENV['RACK_ROOT'] = RACK_ROOT
config_ru = File.expand_path('../../config.ru', __FILE__)
FullRackApp = Rack::Lint.new(Rack::Builder.parse_file(config_ru).first)

FactoryGirl.find_definitions

RSpec::Sidekiq.configure do |config|
  config.warn_when_jobs_not_processed_by_sidekiq = false
end

RSpec.configure do |config|
  config.before(:each) do
    Timecop.freeze(DateTime.now)
  end

  config.after(:each) do
    Timecop.return
  end

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.color_enabled = true
  config.formatter = :documentation
end
