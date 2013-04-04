FactoryGirl.define do
  factory :event, class: WorkflowServer::Models::Event do
    name "WFDecision"
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :decision, class: WorkflowServer::Models::Decision do
    name "WFDecision"
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :signal, class: WorkflowServer::Models::Signal do
    name "WFSignal"
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :flag, class: WorkflowServer::Models::Flag do
    name "WFDecision_completed"
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :continue_as_new_workflow_flag, class: WorkflowServer::Models::ContinueAsNewWorkflowFlag do
    name "WFDecision_completed"
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :timer, class: WorkflowServer::Models::Timer do
    name "WFTimer"
    fires_at Date.tomorrow
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :activity, class: WorkflowServer::Models::Activity do
    name "make_initial_payment"
    client_data({ arguments: ["123", {actor: {actor_id: 100, actor_klass: "PaymentTerm"}}]})
    mode :blocking
    retry_interval 100
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :branch, class: WorkflowServer::Models::Branch do
    name "automate_payment?"
    client_data({ arguments: ["123", {actor: {actor_id: 100, actor_klass: "PaymentTerm"}}]})
    mode :blocking
    retry_interval 100
    workflow
    user { workflow.user }
  end
end

FactoryGirl.define do
  factory :sub_activity, class: WorkflowServer::Models::SubActivity do
    name "import_payment"
    client_data({ arguments: ["123", {actor: {actor_id: 100, actor_klass: "PaymentTerm"}}]})
    mode :blocking
    retry_interval 100
    workflow
    user { workflow.user }
  end
end
