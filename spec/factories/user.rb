FactoryGirl.define do
  factory :user, class: WorkflowServer::Models::User do
    id RSPEC_CONSTANT_USER_CLIENT_ID
  end
end