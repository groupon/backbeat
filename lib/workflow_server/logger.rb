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
        @tid = UUIDTools::UUID.random_create.to_s.slice(0,7)
      elsif option.kind_of?(String)
        @tid = option
      elsif option == :clear
        @tid = nil
      end
      @tid
    end

    def self.logger
      if !class_variable_defined?(:@@logger)
        @@logger = ::Log4r::Logger.new("backbeat_logger")
        @@logger.outputters = Log4r::FileOutputter.new("backbeat_formatter",
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
      define_method(level) do |message|
        WorkflowServer::Logger.logger.__send__(level, {:name => self.to_s, :message => message})
      end
    end
  end

  class OutputFormatter < Log4r::BasicFormatter
    LOG_FORMAT = "%s | %s | %s | %s | %s | %s\n"
    def format(event)
      sprintf(LOG_FORMAT,
              Time.now,
              Process.pid,
              WorkflowServer::Logger.tid || "none",
              Log4r::LNAMES[event.level],
              event.data[:name],
              event.data[:message])
    end
  end

  class DelayedJobLogger
    def self.add(level, text)
      WorkflowServer::Logger.logger.__send__(Log4r::LNAMES[level + 1].to_s.downcase, {:name => self.to_s, :message => text})
    end
  end
end