require 'simplecov'
SimpleCov.start do
  add_filter "/bin/"
  add_filter "/config/"
  add_filter "/spec/"
end

$: << File.expand_path(File.join(__FILE__, "../.."))
$: << File.expand_path(File.join(__FILE__, ".."))

ENV['RACK_ENV'] = "test"

require 'bundler'
require 'helper/mongo'

Bundler.setup
Bundler.require(:default, :test)

require 'app'
require_relative '../services/sidekiq_service'
require_relative '../reports/daily_report'


mongo_path = File.expand_path(File.join(__FILE__, "..", "..", "config", "mongoid.yml"))
Mongoid.load!(mongo_path, :test)


RACK_ROOT = File.expand_path(File.join(__FILE__,'..'))
ENV['RACK_ROOT'] = RACK_ROOT

########### TORQUEBOX SPECIFIC STUFF - START #########################
# delete any deployed yml files before starting
FileUtils.rm_rf("#{WorkflowServer::Config.root}/.torquespec")

# # torquebox has some internal calls to its management service running inside localhost. this
# # conflicts with the webmock stubs
WebMock.disable_net_connect!(:allow_localhost => true)

BACKBEAT_APP = <<-DD_END.gsub(/^ {4}/,'')
    application:
        root: #{WorkflowServer::Config.root}
    environment:
        RACK_ENV: test
    DD_END

require 'accounting_torquespec'

################ TORQUEBOX SPECIFIC STUFF - END #########################

########### MOCK BACKBEAT CLIENT START #################
BACKBEAT_CLIENT_ENDPOINT = "http://backbeat-client:9000"
service = nil
if FakeTorquebox.run_jboss?
  require_relative 'service/backbeat_client'
  service = Service::BackbeatClient.new('backbeat-test')
  BACKBEAT_CLIENT_ENDPOINT = service.start(3010)
end
########### MOCK BACKBEAT CLIENT END   #################

FORMAT_TIME = Proc.new { |time| time.strftime("%Y-%m-%dT%H:%M:%SZ") }

FullRackApp = Rack::Builder.parse_file(File.expand_path(File.join(__FILE__,'..','..','config.ru'))).first

RSPEC_CONSTANT_USER_CLIENT_ID = UUIDTools::UUID.random_create.to_s

FactoryGirl.find_definitions

# should go in unit spec helper
def run_async_jobs
  WorkflowServer::Async::Job.stub(:enqueue) { |job_data| WorkflowServer::Async::Job.new(job_data[:event].id, job_data[:method], job_data[:args], job_data[:max_attempts]).perform }
  yield
  WorkflowServer::Async::Job.unstub(:enqueue)
end

RSpec.configuration.before(:each) do
  Timecop.freeze(DateTime.now)
  response = double('response', code: 200)
  WorkflowServer::Client.stub(post: response)
end

RSpec.configuration.after(:each) do
  Timecop.return
  Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
  service.try(:clear)
end

RSpec.configuration.before(:suite) do
  Helper::Mongo.start(27018)
end

RSpec.configuration.after(:suite) do
  Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
  Helper::Mongo.stop(27018)
end

RSpec.configure do |config|
  # Use color in STDOUT
  config.color_enabled = true

  # Use the specified formatter
  config.formatter = :documentation # :progress, :html, :textmate
end
