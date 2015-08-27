require 'securerandom'

module Backbeat
  module Logging
    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message = nil, &block|
        if block
          message = block.call
        end
        message_with_metadata = {
          time: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'),
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          tid: Logger.tid || 'none',
          level: level,
          logger: self.class.to_s,
          name: self.class.to_s,
          message: message,
          revision: revision
        }
        message_to_log = message_with_metadata.to_json + "\n"
        Logger.log(level, message_to_log)
      end
    end

    def revision
      File.read("REVISION") if File.exists?("REVISION")
    end
  end

  class Logger
    extend Logging

    def self.logger
      @logger ||= create_logger
    end

    def self.log(level, message)
      logger.__send__(level, message)
    end

    def self.create_logger
      if RUBY_PLATFORM == "java"
        require 'torquebox/logger'
        TorqueBox::Logger.new('backbeat_logger')
      else
        ::Logger.new(STDOUT)
      end
    end

    def self.set_logger(logger)
      @logger = logger
    end

    def self.tid_store
      @tid ||= {}
    end

    def self.tid(option = nil)
      if option == :set
        self.tid = SecureRandom.uuid.to_s.slice(0,7)
      elsif option.kind_of?(String)
        self.tid = option
      elsif option == :clear
        self.tid = nil
      end
      tid_store[Thread.current.object_id]
    end

    def self.tid=(value)
      if value.nil?
        tid_store.delete(Thread.current.object_id)
      else
        tid_store[Thread.current.object_id] = value
      end
    end
  end

  class SidekiqLogger
    extend Logging

    def self.crash(message, exception)
      fatal({error: message, backtrace: exception.backtrace})
    end

    def self.add(level, message)
      Logger.logger.add(level, {:name => self.to_s, :message => message}, 'sidekiq_job')
    end
  end
end
