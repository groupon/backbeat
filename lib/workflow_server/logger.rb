require 'torquebox/logger'

module WorkflowServer
  module Logger

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message|
        message_with_metadata = {
          time: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'),
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          tid: WorkflowServer::Logger.tid || 'none',
          level: level,
          source: self.class.to_s,
          name: self.class.to_s,
          message: message
        }
        if WorkflowServer::Config.options[:log_format] == 'json'
          message_to_log = message_with_metadata.to_json + "\n"
        else
          message_to_log = sprintf("%s | %s | %s | %s | %s | %s | %s | %s\n", *message_with_metadata.values)
        end
        WorkflowServer::Logger.logger.__send__(level, message_to_log)
      end
    end

    # Returns a uniq tid
    def self.tid(option = nil)
      if option == :set
        self.tid = UUIDTools::UUID.random_create.to_s.slice(0,7)
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

    def self.logger(log_file = nil)
      @@logger ||= TorqueBox::Logger.new('backbeat_logger')
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
          tid: WorkflowServer::Logger.tid || 'none',
          level: level,
          source: self.to_s,
          message: message
        }
        if WorkflowServer::Config.options[:log_format] == 'json'
          message_to_log = message_with_metadata.to_json + "\n"
        else
          message_to_log = sprintf("%s | %s | %s | %s | %s | %s | %s\n", *message_with_metadata.values)
        end
        WorkflowServer::Logger.logger.__send__(level, message_to_log)
        end
      end
    end
  end

  class DelayedJobLogger
    include WorkflowServer::Logger

    def self.add(level, message)
      WorkflowServer::Logger.logger.add(level, {:name => self.to_s, :message => message}, 'backbeat_delayed_job')
    end
  end

  class SidekiqLogger < DelayedJobLogger
    def self.crash(message, exception)
      self.fatal({error: message, backtrace: exception.backtrace})
    end
  end
end
