FactoryGirl.define do
  factory :v2_workflow, class: V2::Workflow do
    workflow_type 'WFType'
    subject({'subject_klass'=>'PaymentTerm', 'subject_id'=>'100'})
    decider 'PaymentDecider'
    initial_signal :start
    user_id RSPEC_CONSTANT_USER_CLIENT_ID
  end
end
