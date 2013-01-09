
module WorkflowServer
  module Events
    autoload :Event,                    'events/event'
    autoload :Activity,                 'events/activity'
    autoload :Branch,                   'events/branch'
    autoload :Decision,                 'events/decision'
    autoload :Flag,                     'events/flag'
    autoload :Signal,                   'events/signal'
    autoload :SubActivity,              'events/sub_activity'
    autoload :Timer,                    'events/timer'
    autoload :WorkflowCompleteFlag,     'events/workflow_complete_flag'
    autoload :Workflow,                 'events/workflow'
  end
end
