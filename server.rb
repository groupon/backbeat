require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'goliath'
ENV['RACK_ENV'] = Goliath.env.to_s

require 'grape'
require 'api'
require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'
require 'tree'
require 'mongoid_indifferent_access'

class Server < ::Goliath::API
  use Goliath::Rack::Params
  use Api::Authenticate

  def response(env)
    Api::Workflow.call(env)
  end
end