require "spec_helper"
require "service_discovery/description/parameter_descriptor"
require "workflow_server/models/events/event"

describe Api::ServiceDiscoveryResponseCreator do
  class Foo; end

  it "raises an error if the model does not respond to field_hash" do
    expect { described_class.call(Foo, {},) }.to raise_error
  end

  let(:description) { ServiceDiscovery::Description::ParameterDescriptor.new([]) }

  it "builds the response description for the endpoint model" do
    described_class.call(WorkflowServer::Models::Event, description)
    types = description.action.reduce({}) { |memo, (k, v)| memo[k] = v[:type]; memo }
    expect(types[:client_data]).to eq("object")
    expect(types[:client_metadata]).to eq("object")
    [:created_at,
     :id,
     :name,
     :parent_id,
     :status,
     :type,
     :updated_at,
     :workflow_id].each do |attr|
      expect(types[attr]).to eq("string")
     end
  end
end
