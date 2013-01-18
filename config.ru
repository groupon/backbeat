require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'grape'
require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'
require 'tree'
require 'mongoid_indifferent_access'
require 'uuid'
require 'api'

use Rack::Lint if ENV['RACK_ENV'] == 'test'

use Api::CamelCase

use Api::Authenticate

run Api::Workflow