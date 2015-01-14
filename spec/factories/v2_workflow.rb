FactoryGirl.define do
  factory :v2_workflow, class: V2::Workflow do
    workflow_type 'WFType'
    subject({'subjectKlass'=>'PaymentTerm', 'subjectId'=>'100'})
    decider 'PaymentDecider'
    initial_signal :start

    factory :v2_workflow_with_node do
      after(:create) do |workflow|
        FactoryGirl.create(
          :v2_node,
          workflow_id: workflow.id,
          user_id: workflow.user_id
        )
      end
    end

    factory :v2_workflow_with_node_running do
      after(:create) do |workflow|
        signal_node = FactoryGirl.create(:v2_node,
                                         workflow_id: workflow.id,
                                         user_id: workflow.user_id,
                                         current_server_status: :processing_children,
                                         current_client_status: :complete)

        node = FactoryGirl.create(:v2_node,
                                  workflow_id: workflow.id,
                                  user_id: workflow.user_id,
                                  parent_id: signal_node.id,
                                  current_server_status: :sent_to_client,
                                  current_client_status: :received)

        FactoryGirl.create(:v2_client_node_detail,
                           node: node)

        FactoryGirl.create(:v2_node_detail,
                           node: node)
      end
    end
  end
end


