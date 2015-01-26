FactoryGirl.define do
  factory :v2_client_node_detail, class: V2::ClientNodeDetail do
   metadata {}
   data({"could"=>"be", "any"=>"thing"})
  end
end
