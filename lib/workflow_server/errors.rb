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
    def initialize(activity)
      self.message = "#{activity.class}:#{activity.id} tried to make #{activity.next_decision} the next decision but is not allowed to."
    end
  end

  class InvalidEventStatus < StandardError
  end
end
