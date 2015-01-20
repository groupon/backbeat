FactoryGirl.define do
  factory :v2_workflow, class: V2::Node do
    name 'WFType'
    subject({'subjectKlass'=>'PaymentTerm', 'subjectId'=>'100'})
    decider 'PaymentDecider'
    fires_at Time.now
    current_server_status :pending
    current_client_status :pending
    mode :blocking

    factory :v2_workflow_with_node do
      after(:create) do |workflow|
        FactoryGirl.create(
          :v2_node,
          parent: workflow,
          subject: workflow.subject,
          workflow_id: workflow.workflow_id,
          user_id: workflow.user_id
        )
      end
    end

    factory :v2_workflow_with_node_running do
      after(:create) do |workflow|
        signal_node = FactoryGirl.create(
          :v2_node,
          parent: workflow,
          workflow_id: workflow.id,
          user_id: workflow.user_id,
          current_server_status: :processing_children,
          current_client_status: :complete
        )

        FactoryGirl.create(
          :v2_node,
          workflow_id: workflow.id,
          user_id: workflow.user_id,
          parent_id: signal_node.id,
          current_server_status: :sent_to_client,
          current_client_status: :received
        )
      end
    end
  end
end


