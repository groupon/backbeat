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

Squash::Ruby.configure(WorkflowServer::Config.squash_config)
