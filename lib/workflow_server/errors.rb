module WorkflowServer

  class WaitForSubActivity < StandardError
  end

  class TimeOut < StandardError
  end

  class EventNotFound < StandardError
  end

  class EventComplete < StandardError
  end

  class InvalidParameters < StandardError
    def initialize(raw_message)
      @raw_message = raw_message
      super
    end
    def message
      @raw_message
    end
  end

  class InvalidDecisionSelection < StandardError
  end

  class InvalidOperation < StandardError
  end

  class InvalidEventStatus < StandardError
  end

  class HttpError < StandardError
    attr_accessor :response
    def initialize(message, response)
      self.response = response
      super(message)
    end
  end
end
