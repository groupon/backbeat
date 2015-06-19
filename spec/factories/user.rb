FactoryGirl.define do
  BACKBEAT_CLIENT_ENDPOINT = 'http://backbeat-client:9000'

  factory :user, class: Backbeat::User do
    decision_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/decision"
    activity_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/activity"
    notification_endpoint "#{BACKBEAT_CLIENT_ENDPOINT}/notifications"
  end
end
