require 'log4r'


module WorkflowServer
  module Logger

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message|
        WorkflowServer::Logger.logger.__send__(level, {:name => self.class.to_s, :message => message})
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

    def self.logger
      if !class_variable_defined?(:@@logger)
        @@logger = ::Log4r::Logger.new("backbeat_logger")
        log_file = WorkflowServer::Config.log_file
        logger = log_file.nil? ? Log4r::StdoutOutputter : Log4r::FileOutputter
        @@logger.outputters = logger.new("backbeat_formatter",
                                                        level: Log4r::LNAMES.index(WorkflowServer::Config.options[:log_level]) || 0,
                                                        formatter: WorkflowServer::OutputFormatter,
                                                        filename: WorkflowServer::Config.log_file
                                                       )
      end
      @@logger
    end
  end

  module ClassMethods
    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message = nil, &block|
        if message.nil? && !block.nil?
          message = block.call
        end
        WorkflowServer::Logger.logger.__send__(level, {:name => self.to_s, :message => message})
      end
    end
  end

  class OutputFormatter < Log4r::BasicFormatter
    LOG_FORMAT = "%s | %s | %s | %s | %s | %s\n"
    def format(event)
      message = {
        time: Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L"),
        pid: Process.pid,
        thread_id: Thread.current.object_id,
        tid: WorkflowServer::Logger.tid || "none",
        level: Log4r::LNAMES[event.level],
        source: event.data[:name],
        message: event.data[:message]
      }
      case WorkflowServer::Config.options[:log_format]
      when 'json'
        message.to_json + "\n"
      else
        sprintf(LOG_FORMAT, *message.values)
      end
    end
  end

  class DelayedJobLogger
    include WorkflowServer::Logger

    def self.add(level, text)
      WorkflowServer::Logger.logger.__send__(Log4r::LNAMES[level + 1].to_s.downcase, {:name => self.to_s, :message => text})
    end
  end

  class SidekiqLogger < DelayedJobLogger
    def self.crash(string, exception)
      self.error({error: string, backtrace: exception.backtrace})
    end
  end
end
