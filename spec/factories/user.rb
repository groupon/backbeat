FactoryGirl.define do
  factory :user, class: WorkflowServer::Models::User do
    decision_callback_endpoint "http://some_endpoint"
  end
end