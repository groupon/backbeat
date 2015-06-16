require 'sidekiq'
require 'sidekiq-failures'
require 'celluloid'
require_relative '../app'
require 'backbeat/workers/middleware/transaction_id'

module Sidekiq
  class Shutdown < RuntimeError; end
  class CLI; end
end

require 'celluloid/autostart'
require 'sidekiq/processor'
require 'kiqstand'

module Services
  class SidekiqService
    attr_accessor :config, :launcher, :start_failed

    CONFIG_OPTIONS_TO_STRIP = ['config_file', 'daemon', 'environment', 'pidfile', 'require', 'tag', 'options']

    def initialize(opts = {})
      # We merge options here because some keys will cause an error to be raised in torquebox.rb when using the configuration DSL
      @config = opts.reject { |k, _| CONFIG_OPTIONS_TO_STRIP.include?(k) }.merge(opts['options']).symbolize_keys
      @mutex = Mutex.new

      redis_config = YAML::load_file("./config/redis.yml")[WorkflowServer::Config.environment.to_s]

      Sidekiq.configure_server do |config|
        config.redis = { namespace: 'fed_sidekiq', url: "redis://#{redis_config['host']}:#{redis_config['port']}" }
        config.poll_interval = 5
        config.failures_max_count = false
        config.failures_default_mode = :exhausted
        config.server_middleware do |chain|
          chain.add Backbeat::Workers::Middleware::TransactionId
          chain.add Kiqstand::Middleware
        end
      end

    end

    def start
      Thread.new { @mutex.synchronize { run } }
    end

    def stop
      @mutex.synchronize { launcher.stop } if launcher
    end

    def run
      Sidekiq.options.merge!(config)
      Sidekiq.options[:queues] = Sidekiq.options[:queues].to_a
      raise 'Sidekiq workers must have at least 1 queue!' if Sidekiq.options[:queues].size < 1

      Sidekiq::Logger.logger = Backbeat::SidekiqLogger
      Celluloid.logger = Backbeat::SidekiqLogger

      require 'sidekiq/launcher'

      @launcher = Sidekiq::Launcher.new(Sidekiq.options)

      launcher.run
    rescue => e
      puts e.message
      puts e.backtrace

      @start_failed = true
    end
  end
end
