require 'spec_helper'

describe WorkflowServer::Models::Event do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:event) { FactoryGirl.create(:event, workflow: workflow, client_data: {data: 123}, client_metadata: {git_sha: '12de3sdg'}) }
  let(:parent) { FactoryGirl.create(:decision, workflow: workflow) }


  context '#paused' do
    it 'updates status, dismisses watchdogs and notifies parent' do
      event.update_attributes!(parent: parent)
      WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(event)
      event.parent.should_receive(:child_paused).with(event)
      event.paused
      event.status.should == :pause
    end
  end

  context 'notifies parent of resumed' do
    it 'notifies parent' do
      event.update_attributes!(parent: parent)
      event.parent.should_receive(:child_resumed).with(event)
      event.resumed
    end
  end

  context '#child_paused' do
    before do
      @parent = FactoryGirl.create(:event, workflow: workflow, parent: parent)
      event.update_attributes!(parent: @parent)
    end
    context 'child is not fire and forget' do
      it 'dismisses watchdogs and notifies parent' do
        WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@parent)
        parent.should_receive(:child_paused).with(event)
        @parent.child_paused(event)
      end
    end
    context 'child is fire and forget' do
      it 'is a no op' do
        event.stub(fire_and_forget?: true)
        WorkflowServer::Models::Watchdog.should_not_receive(:mass_dismiss)
        parent.should_not_receive(:child_paused)
        @parent.child_paused(event)
      end
    end
  end

  context '#child_resumed' do
    before do
      @parent = FactoryGirl.create(:event, workflow: workflow, parent: parent)
      event.update_attributes!(parent: @parent)
    end
    context 'child is not fire and forget' do
      it 'notifies parent' do
        parent.should_receive(:child_resumed).with(event)
        @parent.child_resumed(event)
      end
    end
  end

  context '#add_decision' do
    it 'creates a decision and stores client data and metadata' do
      event.add_decision(:test)
      event.children.count.should == 1
      decision = event.children.first
      decision.name.should == :test
      decision.client_data.should == {'data' => 123}
      decision.client_metadata.should == {"git_sha" => "12de3sdg"}
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
      decision.status.should == :sent_to_client
    end

    it "starts the interrupt if the server doesn't schedule it" do
      decision = FactoryGirl.create(:decision, workflow: workflow, status: :enqueued)
      event.add_interrupt(:test)
      interrupt = event.children.first
      interrupt.reload.status.should == :sent_to_client
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
      a2 = FactoryGirl.create(:sub_activity, parent: event, workflow: workflow)
      a2.__send__(:parent_decision).should == parent
    end
  end

  context '#method_missing_with_enqueue' do
    it 'schedules a job if the method name begins with enqueue_' do
      WorkflowServer::Async::Job.should_receive(:schedule).with({event: event, method: :test, args: [1,2,3,4], max_attempts:20}, Time.now + 10.minutes)
      event.method_missing_with_enqueue(:enqueue_test, {max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes})
    end
    context 'on error' do
      it 'logs the error and backtrace' do
        WorkflowServer::Async::Job.stub(:schedule).and_raise('some error')
        event.should_receive(:error).with({ id: event.id, method_name: :enqueue_test, args: [{max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes}], error: anything, backtrace: anything })
        expect {
          event.method_missing_with_enqueue(:enqueue_test, {max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes})
        }.to raise_error('some error')
      end
    end
  end
end