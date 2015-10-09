$: << File.expand_path('../../lib', __FILE__)

require 'rubygems'
require 'bundler/setup'

require 'active_record'
require 'sidekiq'
require 'sidekiq_schedulable'
require 'backbeat'

puts "*** Environment is #{Backbeat::Config.environment} ***"

I18n.enforce_available_locales = false

ActiveRecord::Base.include_root_in_json = false
ActiveRecord::Base.establish_connection(Backbeat::Config.database)

Sidekiq.configure_client do |config|
  config.logger.level = Backbeat::Config.log_level
  config.redis = Backbeat::Config.redis
end

Sidekiq.configure_server do |config|
  config.redis = Backbeat::Config.redis
end
