FactoryGirl.define do
  factory :v2_workflow, class: V2::Workflow do
    name 'WFType'
    subject({'subject_klass'=>'PaymentTerm', 'subject_id'=>'100'})
    decider 'PaymentDecider'

    factory :v2_workflow_with_node do
      after(:create) do |workflow|
        FactoryGirl.create(
          :v2_node,
          parent: workflow,
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


