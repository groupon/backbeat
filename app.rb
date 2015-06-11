$: << File.expand_path('../lib', __FILE__)

require 'rubygems'
require 'bundler/setup'
require 'time/marshal_fix'
require 'active_record'
require 'sidekiq'
require 'backbeat'

module Backbeat
  def self.env
    env = Config.environment.to_s
    env == "test" ? "development" : env
  end
end

GIT_REVISION = File.read("#{File.dirname(__FILE__)}/REVISION").chomp rescue 'UNKNOWN'

I18n.enforce_available_locales = false

ActiveRecord::Base.include_root_in_json = false
ActiveRecord::Base.establish_connection(YAML::load_file("#{File.dirname(__FILE__)}/config/database.yml")[Backbeat.env])

redis_config = YAML::load_file("#{File.dirname(__FILE__)}/config/redis.yml")[Backbeat::Config.environment.to_s]
redis_url = "redis://#{redis_config['host']}:#{redis_config['port']}"

Sidekiq.configure_client do |config|
  config.redis = { namespace: 'fed_sidekiq', size: 100, url: redis_url, network_timeout: 5 }
end

Sidekiq.configure_server do |config|
  config.redis = { namespace: 'fed_sidekiq', url: redis_url }
end

puts "*** Environment is #{Backbeat::Config.environment} ***"
