require 'sidekiq'
require 'celluloid'
require_relative '../app'

module Services
  class SidekiqService
    attr_accessor :config, :launcher, :start_failed

    CONFIG_OPTIONS_TO_STRIP = [:config_file, :daemon, :environment, :pidfile, :require, :tag]

    def initialize(opts = {})
      @config = opts.symbolize_keys.reject { |k, _| CONFIG_OPTIONS_TO_STRIP.include?(k) }
      @mutex = Mutex.new
    end

    def start
      Thread.new { @mutex.synchronize { run } }
    end

    def stop
      @mutex.synchronize { launcher.stop } if launcher
    end

    def run
      Sidekiq.options.merge!(config)
      Sidekiq.options[:queues] << 'default' if Sidekiq.options[:queues].empty?

      Sidekiq::Logging.logger = WorkflowServer::SidekiqLogger
      Celluloid.logger = WorkflowServer::SidekiqLogger

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