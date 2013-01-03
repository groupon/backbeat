FactoryGirl.define do
  factory :node, class: Backbeat::Node do
    mode :blocking
    current_server_status :pending
    current_client_status :ready
    name :test_node
    fires_at Time.now

    after(:create) do |node|
      FactoryGirl.create(:node_detail, node: node)
      FactoryGirl.create(:client_node_detail, node: node)
    end
  end
end
