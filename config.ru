$: << File.expand_path(File.join(__FILE__, "..")) # Hack here since require_relative 'app' doesn't work

require 'app'

use Api::Middleware::Log
use Api::Middleware::Heartbeat
use Api::Middleware::Health
use Api::Middleware::SidekiqStats
use Api::Middleware::DelayedJobStats
use Rack::Lint if WorkflowServer::Config.environment == :test
use Api::Middleware::CamelCase
use Api::Middleware::Authenticate

run Api::App
