FactoryGirl.define do
  factory :user, class: WorkflowServer::Models::User do
    id RSPEC_CONSTANT_USER_CLIENT_ID
    decision_endpoint 'http://backbeat_client.com:9000/decision'
    activity_endpoint 'http://backbeat_client.com:9000/activity'
    notification_endpoint 'http://backbeat_client.com:9000/notifications'
  end
end
