require 'securerandom'

module Backbeat
  module Logging
    LEVELS = [:debug, :info, :warn, :error, :fatal]

    LEVELS.each_with_index do |level, level_num|
      define_method(level) do |message = nil, &block|
        if block
          message = block.call
        end
        message_with_metadata = {
          time: Time.now.utc.iso8601(6),
          name: logging_name,
          data: message,
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          tid: Logger.tid || 'none',
          revision: Config.revision
        }
        Logger.add(level_num, message_with_metadata)
      end
    end

    private

    def logging_name
      case self
      when Class
        self.to_s
      when Module
        self.to_s
      else
        self.class.to_s
      end
    end
  end

  class Logger
    extend Logging

    def self.logger
      @logger ||= create_logger
    end

    def self.logger=(logger)
      @logger = logger
    end

    def self.add(level_num, message)
      level = (Logging::LEVELS[level_num] || 'ANY').downcase
      log_data = message.merge({ level: level }).to_json + "\n"
      logger.add(level_num, log_data, nil)
    end

    def self.create_logger
      if defined?(TorqueBox)
        TorqueBox::Logger.new('backbeat_logger')
      else
        logger = ::Logger.new(Config.log_file)
        logger.level = Config.log_level
        logger.formatter = lambda { |_, _, _, msg| msg }
        logger
      end
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
  end
end
