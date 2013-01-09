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
    def initialize(message_as_hash)
      @message_as_hash = message_as_hash
      super
    end
    def message
      @message_as_hash
    end
  end
end
