module WorkflowServer
  module Models
    require_relative  'models/events/event'
    require_relative  'models/events/activity'
    require_relative  'models/events/sub_activity'
    require_relative  'models/events/branch'
    require_relative  'models/events/decision'
    require_relative  'models/events/flag'
    require_relative  'models/events/workflow_complete_flag'
    require_relative  'models/events/signal'
    require_relative  'models/events/timer'
    require_relative  'models/watchdog'
    require_relative  'models/events/workflow'
    require_relative  'models/user'

    MODELS_TEST_CONSTANT = 'xysz'

  end
end
