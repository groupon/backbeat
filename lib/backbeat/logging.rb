require 'securerandom'

module Backbeat
  module Logging
    def self.included(klass)
      klass.extend(ClassMethods)
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message|
        message_with_metadata = {
          time: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'),
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          tid: Logging.tid || 'none',
          level: level,
          logger: self.class.to_s,
          name: self.class.to_s,
          message: message
        }
        message_to_log = message_with_metadata.to_json + "\n"
        Logging.log(level, message_to_log)
      end
    end

    # Returns a uniq tid
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

    def self.tid_store
      @tid ||= {}
    end

    def self.logger
      @@logger ||= create_logger
    end

    def self.create_logger
      if RUBY_PLATFORM == "java"
        require 'torquebox/logger'
        TorqueBox::Logger.new('backbeat_logger')
      else
        ::Logger.new("backbeat_logger")
      end
    end

    def self.set_logger(logger)
      @@logger = logger
    end

    def self.log(level, message)
      logger.__send__(level, message)
    end

    module ClassMethods

      [:debug, :info, :warn, :error, :fatal].each do |level|
        define_method(level) do |message = nil, &block|
          if message.nil? && !block.nil?
            message = block.call
          end
          message_with_metadata = {
            time: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'),
            pid: Process.pid,
            thread_id: Thread.current.object_id,
            tid: Logging.tid || 'none',
            level: level,
            logger: self.to_s,
            message: message
          }
          message_to_log = message_with_metadata.to_json + "\n"
          Logging.log(level, message_to_log)
        end
      end
    end
  end
end
