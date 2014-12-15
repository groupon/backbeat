FactoryGirl.define do
  factory :v2_user, class: V2::User do
    id RSPEC_CONSTANT_USER_CLIENT_ID
    decision_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/decision"
    activity_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/activity"
    notification_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/notifications"
  end
end
