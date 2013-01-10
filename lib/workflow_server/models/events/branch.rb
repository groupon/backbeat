module WorkflowServer
  module Models
    class Branch < Activity
      # A branchs is exactly the same as an activity but provides a distinction between
      # activities that do work and activities that only determine the next decision.
    end
  end
end
