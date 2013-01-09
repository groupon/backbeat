FactoryGirl.define do
  factory :workflow, class: WorkflowServer::Models::Workflow do
    workflow_type "WFType"
    subject_type "PaymentTerm"
    subject_id 100
    decider "PaymentDecider"
    name "WFType"
    user
  end
end