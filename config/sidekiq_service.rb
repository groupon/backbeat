require 'sidekiq'
require 'sidekiq-failures'
require 'celluloid'
require_relative '../config/environment.rb'
require 'backbeat/workers/middleware/transaction_id'

module Sidekiq
  class Shutdown < RuntimeError; end
  class CLI; end
end

require 'celluloid/autostart'
require 'sidekiq/processor'

require 'sidekiq/launcher'
require 'backbeat/logging'
require 'backbeat/workers/middleware/transaction_id'

module Services
  class SidekiqService
    attr_accessor :config, :launcher

    CONFIG_OPTIONS_TO_STRIP = ['config_file', 'daemon', 'environment', 'pidfile', 'require', 'tag', 'options']

    def initialize(opts = {})
      @config = opts.reject { |k, _| CONFIG_OPTIONS_TO_STRIP.include?(k) }.merge(opts['options']).symbolize_keys
      @mutex = Mutex.new

      Sidekiq.configure_server do |config|
        config.redis = { namespace: Backbeat::Config.redis['namespace'], url: Backbeat::Config.redis['url'] }
        config.poll_interval = 5
        config.failures_max_count = false
        config.failures_default_mode = :exhausted
        config.server_middleware do |chain|
          chain.add Backbeat::Workers::Middleware::TransactionId
        end
      end
    end

    def start
      Thread.new do
        @mutex.synchronize { run }
      end
    end

    def stop
      @mutex.synchronize { launcher.stop } if launcher
    end

    def run
      Sidekiq.options.merge!(config)
      Sidekiq.options[:queues] = Sidekiq.options[:queues].to_a
      raise 'Sidekiq workers must have at least 1 queue!' if Sidekiq.options[:queues].size < 1

      Sidekiq.logger = Backbeat::SidekiqLogger
      Celluloid.logger = Backbeat::SidekiqLogger

      @launcher = Sidekiq::Launcher.new(Sidekiq.options)
      launcher.run
    rescue => e
      puts e.message
      puts e.backtrace
    end
  end
end

