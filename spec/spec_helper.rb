$: << File.expand_path(File.join(__FILE__, ".."))
ENV['RACK_ENV'] ||= "test"

require 'bundler'
Bundler.setup(:test)

require './app'
require 'rspec'
require 'rack/test'
require 'factory_girl'
require 'database_cleaner'
require 'timecop'
require 'webmock'
require 'rspec-sidekiq'
require 'pry'
require 'securerandom'

unless ENV["CONSOLE_LOG"]
  log_dir = File.expand_path("../../log", __FILE__)
  Dir.mkdir(log_dir) unless File.exists?(log_dir)
  Backbeat::Logging.set_logger(Logger.new(File.open(File.expand_path("../../log/test.log", __FILE__), "a+")))
end

RACK_ROOT = File.expand_path(File.join(__FILE__,'..'))
ENV['RACK_ROOT'] = RACK_ROOT
FullRackApp = Rack::Builder.parse_file(File.expand_path(File.join(__FILE__,'..','..','config.ru'))).first

FORMAT_TIME = Proc.new { |time| time.strftime("%Y-%m-%dT%H:%M:%SZ") }
BACKBEAT_CLIENT_ENDPOINT = "http://backbeat-client:9000"

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
