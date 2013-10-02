FactoryGirl.define do
  factory :user, class: WorkflowServer::Models::User do
    id RSPEC_CONSTANT_USER_CLIENT_ID
    decision_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/decision"
    activity_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/activity"
    notification_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/notifications"
  end
end
