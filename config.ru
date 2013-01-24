$: << File.expand_path(File.join(__FILE__, "..")) # Hack here since require_relative 'app' doesn't work

require 'app'

use Api::Log

use Rack::Lint if ENV['RACK_ENV'] == 'test'

use Api::CamelCase

use Api::Authenticate

run Api::Workflow