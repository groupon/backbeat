module WorkflowServer
  module Events
    autoload :Event,       'workflow_server/models/events/event'
    autoload :Branch,      'workflow_server/models/events/branch'
    autoload :Activity,    'workflow_server/models/events/activity'
    autoload :SubActivity, 'workflow_server/models/events/sub_activity'
    autoload :Flag,        'workflow_server/models/events/flag'
    autoload :Signal,      'workflow_server/models/events/signal'
    autoload :Timer,       'workflow_server/models/events/timer'
    autoload :Decision,    'workflow_server/models/events/decision'
    autoload :Workflow,    'workflow_server/models/events/workflow'
    autoload :User,        'workflow_server/models/user'

    autoload :WorkflowCompleteFlag,    'workflow_server/models/events/workflow_complete_flag'
  end
end
