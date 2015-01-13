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
  end
end
