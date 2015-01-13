require "spec_helper"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.nodes.first }

  context "client_error" do
    it "marks the client status as errored" do
      V2::Server.fire_event(:client_error, node)
      expect(node.current_client_status).to eq("errored")
    end
  end
end
