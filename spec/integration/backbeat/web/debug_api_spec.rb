require 'spec_helper'
require 'spec/helper/request_helper'

describe Backbeat::Web::DebugApi do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }

  before do
    header 'CLIENT_ID', user.id
  end

  context "GET /debug/error_workflows" do
    it "returns an empty collection if there are no error nodes" do
      workflow

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(body.size).to eq(0)
    end

    it "returns workflows with nodes in client error state" do
      not_errored_workflow = workflow

      errored_workflow = FactoryGirl.create(
        :workflow_with_node,
        name: :a_unique_name,
        user_id: user.id
      )

      errored_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(errored_workflow.id)
    end

    it "returns workflows scoped to the user" do
      user_workflow = workflow
      user_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      other_user_workflow = FactoryGirl.create(
        :workflow_with_node,
        user: FactoryGirl.create(:user)
      )
      other_user_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(user_workflow.id)
    end
  end
end
