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
  end

  class InvalidBranchSelection < StandardError
  end

end
