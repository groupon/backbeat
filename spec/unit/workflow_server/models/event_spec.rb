require 'spec_helper'

describe WorkflowServer::Models::Event do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:event) { FactoryGirl.create(:event, workflow: workflow) }
  let(:parent) { FactoryGirl.create(:decision, workflow: workflow) }

  context '#add_decision' do
    it 'creates a decision' do
      event.add_decision(:test)
      event.children.count.should == 1
      decision = event.children.first
      decision.name.should == :test
    end
    it 'doesnt create parent-child relationship when orphan is true' do
      decisions = workflow.decisions.count
      event.add_decision(:test, true)
      event.children.count.should == 0
      workflow.decisions.count.should == (decisions + 1)
      decision = workflow.decisions.last
      decision.name.should == :test
    end
  end

  context '#add_interrupt' do
    it "adds decision" do
      event.add_interrupt(:test)
      event.children.count.should == 1
      decision = event.children.first
      decision.name.should == :test
      decision.status.should == :enqueued
    end

    it "starts the interrupt if the server doesn't schedule it" do
      decision = FactoryGirl.create(:decision, workflow: workflow, status: :enqueued)
      event.add_interrupt(:test)
      interrupt = event.children.first
      interrupt.reload.status.should == :enqueued
    end
  end

  context '#parent_decision' do
    it "nil when no parent" do
      event.update_attributes!(parent: nil)
      event.__send__(:parent_decision).should == nil
    end
    it "returns the parent if it is decision" do
      event.update_attributes!(parent: parent)
      event.__send__(:parent_decision).should == parent
    end
    it "looks up in hierarchy to find the parent decision" do
      event.update_attributes!(parent: parent)
      a2 = FactoryGirl.create(:sub_activity, parent: event, workflow: @wf)
      a2.__send__(:parent_decision).should == parent
    end
  end
end