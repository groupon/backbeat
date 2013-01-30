$: << File.expand_path(File.join(__FILE__, "..")) # Hack here since require_relative 'app' doesn't work

require 'app'

use Api::Log

use Api::Health

use Rack::Lint if WorkflowServer::Config.environment == :test

use Api::CamelCase

use Api::Authenticate

run Api::Workflow