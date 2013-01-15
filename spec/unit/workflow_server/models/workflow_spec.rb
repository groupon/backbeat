require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Workflow do
  before do
    @event_klass = WorkflowServer::Models::Workflow
    @event_data = {name: :test_flag, workflow_type: :wf_type, subject_type: "PaymentTerm", subject_id: 100, decider: "A::B::C"}
  end

  it_should_behave_like 'events'
end