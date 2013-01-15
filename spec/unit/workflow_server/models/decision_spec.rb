require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Decision do
  before do
    @event_klass = WorkflowServer::Models::Decision
    @event_data = {name: :test_flag}
  end

  it_should_behave_like 'events'
end