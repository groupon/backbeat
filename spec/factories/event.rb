FactoryGirl.define do
  factory :decision, class: WorkflowServer::Models::Decision do
    name "WFDecsion"
    workflow
  end
end

FactoryGirl.define do
  factory :signal, class: WorkflowServer::Models::Signal do
    name "WFSignal"
    workflow
  end
end

FactoryGirl.define do
  factory :flag, class: WorkflowServer::Models::Flag do
    name "WFDecsion_completed"
    workflow
  end
end

FactoryGirl.define do
  factory :timer, class: WorkflowServer::Models::Timer do
    name "WFTimer"
    fires_at Date.tomorrow
    workflow
  end
end

FactoryGirl.define do
  factory :activity, class: WorkflowServer::Models::Activity do
    name "make_initial_payment"
    actor_id 100
    actor_type "PaymentTerm"
    arguments "123"
    mode :blocking
    retry_interval 100
    workflow
  end
end