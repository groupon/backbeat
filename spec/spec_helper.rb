$: << File.expand_path(File.join(__FILE__, ".."))
ENV['RACK_ENV'] = "test"

require 'bundler'
Bundler.setup(:test)

require_relative '../app'
require 'rspec'
require 'rack/test'
require 'factory_girl'
require 'database_cleaner'
require 'timecop'
require 'webmock'
require 'rspec-sidekiq'
require 'pry'
require 'helper/mongo'


if ENV["SIMPLE_COV"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/bin/"
    add_filter "/config/"
    add_filter "/spec/"
  end
end

unless ENV["CONSOLE_LOG"]
  log_dir = File.expand_path("../../log", __FILE__)
  Dir.mkdir(log_dir) unless File.exists?(log_dir)
  WorkflowServer::Logger.set_logger(Logger.new(File.open(File.expand_path("../../log/test.log", __FILE__), "a+")))
end

RACK_ROOT = File.expand_path(File.join(__FILE__,'..'))
ENV['RACK_ROOT'] = RACK_ROOT
FullRackApp = Rack::Builder.parse_file(File.expand_path(File.join(__FILE__,'..','..','config.ru'))).first

FORMAT_TIME = Proc.new { |time| time.strftime("%Y-%m-%dT%H:%M:%SZ") }
RSPEC_CONSTANT_USER_CLIENT_ID = UUIDTools::UUID.random_create.to_s
BACKBEAT_CLIENT_ENDPOINT = "http://backbeat-client:9000"

FactoryGirl.find_definitions

def run_async_jobs
  WorkflowServer::Async::Job.stub(:enqueue) do |job_data|
    WorkflowServer::Workers::SidekiqJobWorker.new.perform(
      job_data[:event].id,
      job_data[:method],
      job_data[:args],
      job_data[:max_attempts]
    )
  end
  yield
  WorkflowServer::Async::Job.unstub(:enqueue)
end

RSpec::Sidekiq.configure do |config|
  config.warn_when_jobs_not_processed_by_sidekiq = false
end

if Backbeat.v2?
  RSpec.configure do |config|
    config.filter_run_including v2: true

    config.before(:each) do
      Timecop.freeze(DateTime.now)
    end

    config.after(:each) do
      Timecop.return
      Mongoid::Sessions.default.collections.select { |c| c.name !~ /system/ }.each(&:drop)
    end

    config.before(:suite) do
      DatabaseCleaner.strategy = :transaction
      DatabaseCleaner.clean_with(:truncation)
      Helper::Mongo.start(27018)
    end

    config.after(:suite) do
      Helper::Mongo.stop(27018)
    end

    config.around(:each) do |example|
      DatabaseCleaner.cleaning do
        example.run
      end
    end

    config.color_enabled = true
    config.formatter = :documentation
  end
else
  RSpec.configure do |config|
    config.filter_run_excluding v2: true

    config.before(:suite) do
      Helper::Mongo.start(27018)
    end

    config.after(:suite) do
      Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
      Helper::Mongo.stop(27018)
    end

    config.before(:each) do
      Timecop.freeze(DateTime.now)
      response = double('response', code: 200)
      WorkflowServer::Client.stub(post: response)
    end

    config.after(:each) do
      Timecop.return
      Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
    end

    config.color_enabled = true
    config.formatter = :documentation
  end
end

###### FOR TRANSACTION SUPPORT #########
# We need this till we have tokumx 1.2.0 on build and dev machines
module WorkflowServer
  module Models
    class Event
      class << self
        alias_method :transaction_original, :transaction # useful to test unit specs
      end
      def self.transaction
        yield
      end
    end
  end
end
###### FOR TRANSACTION SUPPORT END #####
