require 'spec_helper'

describe WorkflowServer::Models::Event do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:event) { FactoryGirl.create(:event, workflow: workflow, client_data: {data: 123}, client_metadata: {git_sha: '12de3sdg'}) }
  let(:parent) { FactoryGirl.create(:decision, workflow: workflow) }

  context '#resolved' do
    it 'updates the status to resolved' do
      event.resolved

      event.status.should == :resolved
    end

    it 'sets the reason if passed' do
      reason = 'Becasue Matt said so!'
      event.resolved(reason: reason)

      event.status_history.first[:error][:message].should == reason
    end

    it 'continues on if continue option is set' do
      event.stub(parent: parent)

      parent.should_receive(:enqueue_child_completed).with(args: [event.id])

      event.resolved(continue: true)
    end

    it 'completes the workflow if the complete_workflow option is set' do
      event.workflow.should_receive(:update_status!).with(:complete)

      event.resolved(complete_workflow: true)
    end
  end

  context '#paused' do
    it 'updates status, dismisses watchdogs and notifies parent' do
      event.stub(parent: parent)
      event.update_attributes!(parent: parent)
      #WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(event)
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
        #WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@parent)
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
    it 'send to sidekiq if fires_at is nil' do
      WorkflowServer::Async::Job.should_receive(:enqueue).with({
        event: subject,
        method: :testing_method_missing,
        args: [:arg1, :arg2],
        max_attempts: anything()
      }, Time.now)

      subject.enqueue_testing_method_missing(args: [:arg1, :arg2])
    end

    it 'sends to sidekiq if fires_at is now' do
      WorkflowServer::Async::Job.should_receive(:enqueue).with({
        event: subject,
        method: :testing_method_missing,
        args: [:arg1, :arg2],
        max_attempts: anything()
      }, Time.now)

      subject.enqueue_testing_method_missing(args: [:arg1, :arg2], fires_at: Time.now)
    end

    it 'sends to sidekiq if fires_at is before now' do
      WorkflowServer::Async::Job.should_receive(:enqueue).with({
        event: subject,
        method: :testing_method_missing,
        args: [:arg1, :arg2],
        max_attempts: anything()
      }, Time.now - 30)

      subject.enqueue_testing_method_missing(args: [:arg1, :arg2], fires_at: Time.now - 30)
    end

    it 'sends to sidekiq if processor is :sidekiq' do
      WorkflowServer::Async::Job.should_receive(:enqueue).with({
        event: subject,
        method: :testing_method_missing,
        args: [:arg1, :arg2],
        max_attempts: anything()
      }, Time.now)

      subject.enqueue_testing_method_missing(args: [:arg1, :arg2], processor: :sidekiq)
    end

    it 'sends to DelayedJob if processor is not :sidekiq and run time is after now' do
      WorkflowServer::Async::Job.should_receive(:schedule).with({
        event: subject,
        method: :testing_method_missing,
        args: [:arg1, :arg2],
        max_attempts: anything()
      }, Time.now + 30)

      subject.enqueue_testing_method_missing(args: [:arg1, :arg2], fires_at: Time.now + 30)
    end

    it 'schedules a job if the method name begins with enqueue_' do
      WorkflowServer::Async::Job.should_receive(:schedule).with({event: event, method: :test, args: [1,2,3,4], max_attempts:20}, Time.now + 10.minutes).and_return(double('job', id: 100))
      event.method_missing_with_enqueue(:enqueue_test, {max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes})
    end

    context 'on error' do
      context 'Redis::CannotConnectError' do
        it 'schedules the job to try again in 60 seconds' do
          WorkflowServer::Async::Job.stub(:enqueue).and_raise(Redis::CannotConnectError.new('o shit redis is not working'))

          WorkflowServer::Async::Job.should_receive(:schedule).with({ event: event, method: :test, args: [1, 2, 3, 4], max_attempts: 20}, Time.now + 60)

          event.method_missing_with_enqueue(:enqueue_test, {max_attempts: 20, args: [1, 2, 3, 4]})
        end
      end
      context 'Exception' do
        it 'logs the error and backtrace' do
          WorkflowServer::Async::Job.stub(:schedule).and_raise('some error')
          event.should_receive(:error).with({ id: event.id, method_name: :enqueue_test, args: [{max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes}], error: anything, backtrace: anything })
          expect {
            event.method_missing_with_enqueue(:enqueue_test, {max_attempts: 20, args: [1, 2, 3, 4], fires_at: Time.now + 10.minutes})
          }.to raise_error('some error')
        end
      end
    end

    context '#with_lock_with_defaults' do
      it 'merges in the default options' do
        event.should_receive(:with_lock_without_defaults).with(retry_sleep: 0.5, retries: 10, timeout: 10)
        event.with_lock_with_defaults {'NOTHING'}
      end

      it 'rescues Mongoid::Locker::LockError and reraises it as a Backbeat::TransientError' do
        event.stub(:with_lock_without_defaults).and_raise(Mongoid::Locker::LockError.new('test'))
        expect{
          event.with_lock_with_defaults {'NOTHING'}
        }.to raise_error(Backbeat::TransientError)
      end
    end

    context "#self.transaction" do
      before do
        WorkflowServer::Models::Workflow.any_instance.stub(next_sequence: 10)
      end
      it "runs inside a transaction and commits the transaction" do
        command_args = []
        WorkflowServer::Models::Event.collection.database.class.any_instance.stub(:command){ |options|
          command_args << options
        }
        event.class.transaction_original {}
        command_args.should == [{beginTransaction: 1}, {commitTransaction: 1}]
      end
      it "runs inside a transaction and rolls back on error (doesnt commit the transaction)" do
        command_args = []
        WorkflowServer::Models::Event.collection.database.class.any_instance.stub(:command){ |options|
          command_args << options
        }
        expect {
          event.class.transaction_original { raise "Exception" }
        }.to raise_error("Exception")
        command_args.should == [{beginTransaction: 1}, {rollbackTransaction: 1}]
      end
      it "runs nested transactions" do
        command_args = []
        WorkflowServer::Models::Event.collection.database.class.any_instance.stub(:command){ |options|
          command_args << options
        }
        event.class.transaction_original {
          event.class.transaction_original {}
        }
        command_args.should == [{beginTransaction: 1}, {commitTransaction: 1}]
      end
    end
  end
  context "#next_sequence" do
    context "old workflows" do
      context "someone calls save on workflow, _event_sequence becomes 0" do
        it "assings event sequence to STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS and returns the next sequence number" do
          # old workflows will have some sequence number other than 0
          workflow.update_attributes!(sequence: 100, _event_sequence: 0)
          event = FactoryGirl.create(:event, workflow: workflow)
          output = event.sequence
          output.should == WorkflowServer::Models::Workflow::STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS + 1
          workflow.reload
          workflow._event_sequence.should == WorkflowServer::Models::Workflow::STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS + 1
        end
      end
      context "just an old workflow (so _event_sequence is never set)" do
        it "assings event sequence to STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS and returns the next sequence number" do
          # old workflows will have some sequence number other than 0
          workflow.update_attributes!(sequence: 100)
          workflow.unset(:_event_sequence)
          event = FactoryGirl.create(:event, workflow: workflow)
          output = event.sequence
          output.should == WorkflowServer::Models::Workflow::STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS + 1
          workflow.reload
          workflow._event_sequence.should == WorkflowServer::Models::Workflow::STARTING_SEQUENCE_NUMBER_FOR_OLD_WORKFLOWS + 1
        end
      end
    end
    context "new workflows" do
      it "starts from 0" do
        event = FactoryGirl.create(:event, workflow: workflow)
        output = event.sequence
        output.should == 2
        workflow.reload
        workflow._event_sequence.should == 2
        workflow.sequence.should == 1
      end
    end
  end

  context "#update_status" do
    it "updates the status and status-history" do
      event.update_status!(:executing)
      event.status.should == :executing
      event.status_history.should == [{from: :open,
            to: :executing,
            at: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'),
            tid: nil}]
    end

    context "stale object" do
      it "skips updating the status if the current object is stale" do
        pending "We will have to optimize this code since it is not working as well as expected. Naren"
        event.update_attributes!(status: :close)
        event.status = :open # mock as if we have a stale object
        event.update_status!(:executing)
        event.status.should_not == :executing
        event.status_history.should == []
      end
    end
  end
end
