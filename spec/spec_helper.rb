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

mongo_path = File.expand_path(File.join(__FILE__, "..", "..", "config", "mongoid.yml"))
Mongoid.load!(mongo_path, :test)

require_relative("support/fake_resque.rb")
module Resque
  def enqueue_to(*args)
  end
  def enqueue(*args)
    # we can't stub here.
  end
end

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
    messaging:
        /queues/accounting_backbeat_internal:
             WorkflowServer::Async::MessageProcessor:
                  synchronous: true
    DD_END

################ TORQUEBOX SPECIFIC STUFF - END #########################

require_relative 'fake_torquebox'

########### MOCK BACKBEAT CLIENT START #################
BACKBEAT_CLIENT_ENDPOINT = "http://backbeat-client:9000"
service = nil
if FakeTorquebox.run_jboss?
  require 'service'
  service = Service::BackbeatClient.new('backbeat-test')
  BACKBEAT_CLIENT_ENDPOINT = service.start(3010)
end
########### MOCK BACKBEAT CLIENT END   #################

FullRackApp = Rack::Builder.parse_file(File.expand_path(File.join(__FILE__,'..','..','config.ru'))).first

RSPEC_CONSTANT_USER_CLIENT_ID = UUIDTools::UUID.random_create.to_s

FactoryGirl.find_definitions

RSpec.configuration.before(:each) do
  Timecop.freeze(DateTime.now)
  @start = Time.now
  response = double('response', code: 200)
  WorkflowServer::Client.stub(post: response)
end

RSpec.configuration.after(:each) do
  ap "Time taken for this spec #{Time.now - @start}"
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
  FileUtils.rm_rf("#{WorkflowServer::Config.root}/.torquespec")
end

RSpec.configure do |config|
  # Use color in STDOUT
  config.color_enabled = true

  # Use the specified formatter
  config.formatter = :documentation # :progress, :html, :textmate
end
