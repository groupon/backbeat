FactoryGirl.define do
  factory :v2_user, class: V2::User do
    decision_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/decision"
    activity_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/activity"
    notification_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/notifications"
  end
end
