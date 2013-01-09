module WorkflowServer
  module Models
    autoload :Events,      'workflow_server/models/events'
    autoload :Watchdog,    'workflow_server/models/watchdog'
    autoload :Event,       'workflow_server/models/events/event'
    autoload :Activity,    'workflow_server/models/events/activity'
    autoload :SubActivity, 'workflow_server/models/events/sub_activity'
    autoload :Flag,        'workflow_server/models/events/flag'
    autoload :Signal,      'workflow_server/models/events/signal'
    autoload :Timer,       'workflow_server/models/events/timer'
    autoload :Decision,    'workflow_server/models/events/decision'
    autoload :Workflow,    'workflow_server/models/events/workflow'
  end
end
