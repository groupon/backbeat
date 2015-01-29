require 'spec_helper'
require 'spec/helper/request_helper'

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow_with_node, user: v2_user) }

  before do
    header 'CLIENT_ID', v2_user.id
  end

  def do_get(path)
    response = get(path)
    JSON.parse(response.body)
  end

  context "GET /debug/error_workflows" do
    it "returns workflows with nodes in error state" do
      not_errored_workflow = v2_workflow

      errored_workflow = FactoryGirl.create(
        :v2_workflow_with_node,
        user: v2_user
      )
      errored_workflow.children.first.update_attributes(
        current_server_status: :errored
      )

      response = do_get("/debug/error_workflows")

      expect(response.size).to eq(1)
      expect(response.first["id"]).to eq(errored_workflow.id)
    end
  end
end
