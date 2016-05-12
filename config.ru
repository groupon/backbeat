require File.expand_path('../config/environment',  __FILE__)

require 'backbeat/web'
require 'sidekiq/web'

class SidekiqUI < Grape::API
  mount Sidekiq::Web => '/sidekiq'
end

# run Rack::Cascade.new([Backbeat::Web::App, SidekiqUI])
run Backbeat::Web::App
