require_relative 'app'

use Rack::Lint if ENV['RACK_ENV'] == 'test'

use Api::CamelCase

use Api::Authenticate

run Api::Workflow