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

#['JBOSS_HOME', 'JRUBY_HOME', 'TORQUEBOX_HOME'].each {|var| ENV[var] = nil }
RACK_ROOT = File.expand_path(File.join(__FILE__,'..'))
ENV['RACK_ROOT'] = RACK_ROOT

require 'torquespec'

TorqueSpec.configure do |config|
  config.jboss_home = '/Users/milinostroza/.immutant/current/jboss'
end

  WebMock.disable_net_connect!(:allow_localhost => true)

BACKBEAT_APP = <<-DD_END.gsub(/^ {4}/,'')
     application:
       root: #{WorkflowServer::Config.root}
       env: test
   DD_END

FullRackApp = Rack::Builder.parse_file(File.expand_path(File.join(__FILE__,'..','..','config.ru'))).first


RSPEC_CONSTANT_USER_CLIENT_ID = UUIDTools::UUID.random_create.to_s

FactoryGirl.find_definitions

RSpec.configuration.before(:each) do
  Timecop.freeze(Time.now)
end

RSpec.configuration.after(:each) do
  Timecop.return
  Mongoid::Sessions.default.collections.select {|c| c.name !~ /system/ }.each(&:drop)
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
