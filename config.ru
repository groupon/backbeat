$: << File.expand_path(File.join(__FILE__, ".."))

require './app'
require 'backbeat/web'

use Rack::Lint if Backbeat::Config.environment == :test
use ActiveRecord::ConnectionAdapters::ConnectionManagement
use Backbeat::Web::Middleware::Log
use Backbeat::Web::Middleware::Heartbeat
use Backbeat::Web::Middleware::Health
use Backbeat::Web::Middleware::SidekiqStats
use Backbeat::Web::Middleware::CamelCase
use Backbeat::Web::Middleware::Authenticate

run Backbeat::API
