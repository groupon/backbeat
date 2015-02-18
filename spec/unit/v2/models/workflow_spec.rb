require "spec_helper"

describe V2::Workflow, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }

  context "workflow_id" do
    it "returns the id" do
      expect(workflow.workflow_id).to eq(workflow.id)
    end
  end

  context "children" do
    it "returns nodes with the same workflow_id and no parent node" do
      node = workflow.nodes.first
      FactoryGirl.create(
        :v2_node,
        user: user,
        workflow_id: workflow.id,
        parent_id: node.id
      )
      expect(workflow.children.count).to eq(1)
      expect(workflow.children.first).to eq(node)
    end
  end

  include Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = capture(:stdout) do
        workflow.print_tree
      end

      expect(output).to eq(V2::WorkflowTree.to_string(workflow) + "\n")
    end
  end

  context "complete!" do
    it "sets the complete attribute to true" do
      expect(workflow.complete?).to eq(false)

      workflow.complete!

      expect(workflow.complete?).to eq(true)
    end
  end

  context "find_or_create_from_v1" do
    let(:v1_user) { FactoryGirl.create(:v1_user) }
    let(:v2_user) { FactoryGirl.create(:v2_user) }
    let(:v1_workflow) { FactoryGirl.create(:workflow, user: v1_user) }

    it "returns v2 workflow if it already exists" do
      v2_workflow = FactoryGirl.create(:v2_workflow, uuid: v1_workflow.id, user: v2_user)
      workflow = V2::Workflow.find_or_create_from_v1(v1_workflow, v2_user.id)

      expect(workflow.class.to_s).to eq("V2::Workflow")
      expect(workflow.id).to eq(v2_workflow.id)
    end

    it "creates v2 workflow if it does not exists" do
      expect(V2::Workflow.count).to eq(0)

      workflow = V2::Workflow.find_or_create_from_v1(v1_workflow, v2_user.id)

      expect(V2::Workflow.count).to eq(1)
      expect(workflow.name).to eq(v1_workflow.name)
      expect(workflow.complete).to eq(false)
      expect(workflow.decider).to eq(v1_workflow.decider)
      expect(workflow.subject).to eq(v1_workflow.subject)
      expect(workflow.uuid).to eq(v1_workflow.id.gsub("-", ""))
      expect(workflow.user_id).to eq(v2_user.id)
    end
  end
end
