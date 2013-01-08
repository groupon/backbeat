require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'goliath'
require 'api'
require 'awesome_print'

#require 'workflow_server'

class Server < ::Goliath::API
  def response(env)
    Api::Workflow.call(env)
  end
end