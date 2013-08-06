require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'mongoid_auto_increment'
require 'delayed_job_mongoid'
require 'mongoid_indifferent_access'
require 'uuidtools'
require 'log4r'
require 'service-discovery'
require 'grape'
require 'api'
require 'workflow_server'
require 'resque'

Squash::Ruby.configure(WorkflowServer::Config.squash_config)

config = YAML::load_file("#{File.dirname(__FILE__)}/config/redis.yml")[ENV['RACK_ENV']]
Resque.redis = Redis.new(:host => config['host'], :port => config['port'])

require 'newrelic_rpm'
