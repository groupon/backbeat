FactoryGirl.define do
  factory :workflow, class: WorkflowServer::Models::Workflow do
    workflow_type 'WFType'
    subject ({'subject_klass'=>'PaymentTerm', 'subject_id'=>'100'})
    decider 'PaymentDecider'
    name 'WFType'
    user
  end
end
