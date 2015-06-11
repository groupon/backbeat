require "spec_helper"
require "backbeat/helpers/colorize"

describe Backbeat::WorkflowTree do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  def add_node(parent, name)
    FactoryGirl.create(
      :node,
      parent: parent,
      workflow_id: workflow.id,
      name: name,
      user: user
    )
  end

  def uuid(node)
    node.id.to_s
  end

  context "traverse" do
    it "calls the block for each node in the tree" do
      child_1 = add_node(workflow, "Workflow child")
      child_2 = add_node(workflow, "Another Workflow child")
      child_3 = add_node(workflow.children.first, "Nested child")

      names = []
      Backbeat::WorkflowTree.new(workflow).traverse do |node|
        names << node.name
      end

      expect(names).to eq([workflow.name, child_1.name, child_3.name, child_2.name])
    end

    it "skips the root node if the root option is false" do
      child_1 = add_node(workflow, "Workflow child")

      names = []
      Backbeat::WorkflowTree.new(workflow).traverse(root: false) do |node|
        names << node.name
      end

      expect(names).to eq([child_1.name])
    end
  end

  context "to_hash" do
    it "returns the tree as a hash with no children" do
      expect(Backbeat::WorkflowTree.to_hash(workflow)).to eq({
        id: uuid(workflow),
        current_server_status: nil,
        current_client_status: nil,
        name: workflow.name,
        children: []
      })
    end

    it "returns the tree as a hash with children" do
      add_node(workflow, "Workflow child")

      expect(Backbeat::WorkflowTree.to_hash(workflow)).to eq({
        id: uuid(workflow),
        current_server_status: nil,
        current_client_status: nil,
        name: workflow.name,
        children: [
          {
            id: uuid(workflow.children.first),
            current_server_status: "pending",
            current_client_status: "ready",
            name: "Workflow child",
            children: []
          }
        ]
      })
    end

    it "returns the tree as a hash with nested children" do
      add_node(workflow, "Workflow child")
      add_node(workflow, "Another Workflow child")
      add_node(workflow.children.first, "Nested child")

      expect(Backbeat::WorkflowTree.to_hash(workflow)).to eq({
        id: uuid(workflow),
        current_server_status: nil,
        current_client_status: nil,
        name: workflow.name,
        children: [
          {
            id: uuid(workflow.children.first),
            current_server_status: "pending",
            current_client_status: "ready",
            name: "Workflow child",
            children: [
              {
                id: uuid(workflow.children.first.children.first),
                current_server_status: "pending",
                current_client_status: "ready",
                name: "Nested child",
                children: []
              }
            ]
          },
          {
            id: uuid(workflow.children.last),
            current_server_status: "pending",
            current_client_status: "ready",
            name: "Another Workflow child",
            children: []
          }
        ]
      })
    end
  end

  include Backbeat::Colorize

  context "to_string" do
    it "returns the tree as a string with no children" do
      expect(Backbeat::WorkflowTree.to_string(workflow)).to eq(
        "\n#{uuid(workflow)}#{cyan("|--")}#{workflow.name}"
      )
    end

    it "returns the tree as a string with children" do
      child = add_node(workflow, "Workflow child")
      child.update_attributes(current_server_status: :errored)

      expect(Backbeat::WorkflowTree.to_string(workflow)).to eq(
        "\n#{uuid(workflow)}#{cyan("|--")}#{workflow.name}"\
        "\n#{uuid(child)}#{cyan("   |--")}#{red("#{child.name} - server: #{child.current_server_status}, client: #{child.current_client_status}")}"
      )
    end

    it "returns the tree as a hash with nested children" do
      child_1 = add_node(workflow, "Workflow child")
      child_2 = add_node(workflow, "Another Workflow child")
      child_3 = add_node(workflow.children.first, "Nested child")
      child_4 = add_node(workflow, "An Errored Workflow child")
      child_5 = add_node(workflow, "A Ready Workflow child")

      child_1.update_attributes(current_server_status: :processing_children)
      child_2.update_attributes(current_server_status: :complete, current_client_status: :complete)
      child_3.update_attributes(current_server_status: :sent_to_client)
      child_4.update_attributes(current_server_status: :ready, current_client_status: :errored)
      child_5.update_attributes(current_server_status: :ready, current_client_status: :ready)

      expect(Backbeat::WorkflowTree.to_string(workflow)).to eq(
        "\n#{uuid(workflow)}#{cyan("|--")}#{workflow.name}"\
        "\n#{uuid(child_1)}#{cyan("   |--")}#{yellow("#{child_1.name} - server: #{child_1.current_server_status}, client: #{child_1.current_client_status}")}"\
        "\n#{uuid(child_3)}#{cyan("      |--")}#{yellow("#{child_3.name} - server: #{child_3.current_server_status}, client: #{child_3.current_client_status}")}"\
        "\n#{uuid(child_2)}#{cyan("   |--")}#{green("#{child_2.name} - server: #{child_2.current_server_status}, client: #{child_2.current_client_status}")}"\
        "\n#{uuid(child_4)}#{cyan("   |--")}#{red("#{child_4.name} - server: #{child_4.current_server_status}, client: #{child_4.current_client_status}")}"\
        "\n#{uuid(child_5)}#{cyan("   |--")}#{white("#{child_5.name} - server: #{child_5.current_server_status}, client: #{child_5.current_client_status}")}"
      )
    end
  end
end
