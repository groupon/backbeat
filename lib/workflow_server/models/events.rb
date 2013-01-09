
module WorkflowServer
  module Events
    autoload :Event,    'events/event'
    autoload :Activity, 'events/activity'
    autoload :SubActivity, 'events/sub_activity'
    autoload :Flag, 'events/flag'
    autoload :Signal, 'events/signal'
    autoload :Timer, 'events/timer'
    autoload :Decision, 'events/decision'
    autoload :Workflow, 'events/workflow'
  end
end
