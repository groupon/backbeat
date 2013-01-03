module WorkflowServer
  module Models
    class SubActivity < Activity
      # Nothing special here. This class is used to separate top-level activities from lower level activities.
      # Each sub-activity has a parent that can either be an activity or a sub-activity
      # Each activity / sub-activity can have multiple sub-activities
    end
  end
end
