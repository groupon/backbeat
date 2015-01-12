FactoryGirl.define do
  factory :client_decision, class: Hash do
     initialize_with { attributes }
  end

  factory :client_post_node_activity, class: Hash do
    id "some_id"
    mode :blocking
    type 'activity'
    name 'name_1'
    client_data { {could: :be, any: :thing} }
    always false
    retry_interval 6.hours
    time_out 3.hours
    valid_next_decisions [:some, :thing]
    orphan_decision false
    initialize_with { attributes }
  end

  factory :client_activity_post_to_decision, class: Hash do
     type 'activity'
     name 'name_1'
     client_data { {could: :be, any: :thing} }
     mode :blocking
     always false
     retry_interval 6.hours
     time_out 3.hours
    valid_next_decisions [:some, :thing]
    orphan_decision false
    initialize_with { attributes }
  end
end
