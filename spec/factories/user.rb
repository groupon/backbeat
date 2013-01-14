FactoryGirl.define do
  factory :user, class: WorkflowServer::Models::User do
    client_id RSPEC_CONSTANT_USER_CLIENT_ID
    decision_callback_endpoint "http://some_endpoint"
  end
end