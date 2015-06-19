require File.expand_path('../config/environment',  __FILE__)

require 'backbeat/web'

use ActiveRecord::ConnectionAdapters::ConnectionManagement
use Backbeat::Web::Middleware::Log
use Backbeat::Web::Middleware::Heartbeat
use Backbeat::Web::Middleware::Health
use Backbeat::Web::Middleware::SidekiqStats
use Backbeat::Web::Middleware::CamelCase
use Backbeat::Web::Middleware::Authenticate

run Backbeat::API
