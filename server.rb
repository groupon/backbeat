require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'goliath'
require 'api'
require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'
require 'tree'
require 'mongoid_indifferent_access'

#require 'workflow_server'

class Server < ::Goliath::API

  use Api::Authenticate

  def response(env)
    Api::Workflow.call(env)
  end
end