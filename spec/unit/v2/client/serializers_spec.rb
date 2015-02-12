require "spec_helper"

describe "Serializers", v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  context "NodeSerializer" do
    it "serializes a node" do
      expect(V2::Client::NodeSerializer.call(node)).to eq(
        {
          id: node.id,
          mode: node.mode,
          name: node.name,
          workflow_id: node.workflow_id,
          parent_id: node.parent_id,
          user_id: node.user_id,
          client_data: node.client_data,
          metadata: node.client_metadata,
          subject: node.subject,
          decider: node.decider
        }
      )
    end
  end

  context "NotificationSerializer" do
    it "serializers a notification" do
      expect(V2::Client::NotificationSerializer.call(node, "A message")).to eq(
        {
          notification: {
            type: "V2::Node",
            id: node.id,
            name: node.name,
            subject: node.subject,
            message: "A message"
          },
          error: nil
        }
      )
    end
  end

  context "ErrorSerializer" do
    it "formats the hash for StandardErrors" do
      error = StandardError.new('some_error')
      expect(V2::Client::ErrorSerializer.call(error)).to eq({
        error_klass: error.class.to_s,
        message: error.message
      })
    end

    it "adds backtrace if it exists" do
      begin
        raise StandardError.new('some_error')
      rescue => error
        expect(V2::Client::ErrorSerializer.call(error)).to eq({
          error_klass: error.class.to_s,
          message: error.message,
          backtrace: error.backtrace
        })
      end
    end

    it "formats the hash for strings" do
      error = "blah"
      expect(V2::Client::ErrorSerializer.call(error)).to eq({
        error_klass: error.class.to_s,
        message: error
      })
    end

    it "doesn't format for other other class types" do
      error = 1
      expect(V2::Client::ErrorSerializer.call(error)).to eq(1)
    end
  end
end
