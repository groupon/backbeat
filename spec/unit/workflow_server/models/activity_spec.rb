require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Activity do
  let(:user) { FactoryGirl.create(:user) }

  before do
    @event_klass = WorkflowServer::Models::Activity
    @wf = FactoryGirl.create(:workflow, user: user)
    @a1 = FactoryGirl.create(:activity, workflow: @wf).reload
    @event = @a1
  end
  it_should_behave_like 'events'

  it "activities cannot be blocking and always" do
    expect {
      WorkflowServer::Models::Activity.create!(name: :some_activity, mode: :blocking, always: true)
    }.to raise_error(Mongoid::Errors::Validations)
  end

  context "#start" do
    it "schedules a job to perform_activity and goes into enqueued state" do
      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: @a1, method: :send_to_client, args: nil, max_attempts: 25})
      @a1.start
      @a1.status.should == :executing
    end
  end

  context "#restart" do
    it "updates status to :restarting before calling start" do
      @a1.update_status!(:timeout)
      @a1.should_receive(:update_status!).with(:restarting)
      @a1.should_receive(:start).and_raise

      expect{@a1.restart}.to raise_error
    end

    it "calls start" do
      @a1.update_status!(:timeout)
      @a1.should_receive(:start)

      @a1.restart
    end

    it "raises an error if the current status is not either :error or :timeout" do
      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: @a1, method: :send_to_client, args: nil, max_attempts: 25})
        .exactly(2).times

      @a1.update_status!(:open)
      expect {
        @a1.restart
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to restarting")

      @a1.update_status!(:error)
      expect {
        @a1.restart
      }.to_not raise_error

      @a1.update_status!(:timeout)
      expect {
        @a1.restart
      }.to_not raise_error
    end
  end

  context '#resumed' do
    it 'calls send_to_client' do
      @a1.should_receive(:send_to_client)
      @a1.resumed
    end
  end

  context '#child_resumed' do
    context 'child is fire_and_forget' do
      it 'no-op' do
        @a1.update_attributes!(time_out: 10)
        a2 = FactoryGirl.create(:activity, mode: :fire_and_forget, parent: @a1, workflow: @wf)
        WorkflowServer::Models::Watchdog.should_not_receive(:start)
        @a1.child_resumed(a2)
      end
    end
    context 'child is not fire_and_forget' do
      it 'no-op' do
        @a1.update_attributes!(time_out: 10)
        a2 = FactoryGirl.create(:activity, mode: :non_blocking, parent: @a1, workflow: @wf)
        WorkflowServer::Models::Watchdog.should_receive(:start).with(@a1, :timeout, 10)
        @a1.child_resumed(a2)
      end
    end
  end

  context "#send_to_client" do
    before do
      @a1.update_attributes!(time_out: 10)
    end
    context 'workflow is paused' do
      before do
        @wf.update_status!(:pause)
      end
      it 'puts itself in paused state and doesn\'t go to client' do
        WorkflowServer::Client.should_not_receive(:perform_activity)
        WorkflowServer::Models::Watchdog.should_not_receive(:start)
        @a1.send(:send_to_client)
        @a1.status.should == :pause
      end
    end
    context 'workflow is not paused' do
      it "calls out to workflow async client to perform activity" do
        WorkflowServer::Client.should_receive(:perform_activity).with(@a1)
        WorkflowServer::Models::Watchdog.should_receive(:start).with(@a1, :timeout, 10)
        @a1.send(:send_to_client)
        @a1.status.should == :executing
      end
    end
  end

  context "on complete" do
    context "no subactivities running" do
      before do
        @a1.stub(subactivities_running?: false)

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .twice
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil})
        @activity = FactoryGirl.create(:activity, parent: FactoryGirl.create(:decision, workflow: @wf), workflow: @wf)
      end

      context "next decision is set" do
        it "schedules a decision task and goes to complete state" do
          @activity.update_attributes!(next_decision: :decision_blah_blah)

          WorkflowServer::Async::Job.should_receive(:enqueue)
            .with({event: kind_of(WorkflowServer::Models::Decision), method: :send_to_client, args: nil, max_attempts: 25})
          WorkflowServer::Async::Job.should_receive(:enqueue)
            .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil})

          @activity.completed
          @activity.reload.children.count.should == 1
          decision = @activity.children.first
          decision.name.should == :decision_blah_blah
          @activity.status.should == :complete
        end
      end
      context "next decision is nil" do
        it "no decision event scheduled" do
          @activity.update_attributes!(next_decision: nil)
          @activity.completed
          @activity.reload.children.count.should == 0
          @activity.status.should == :complete
        end
      end
      context "next decision is 'none'" do
        it "no decision event scheduled" do
          @activity.update_attributes!(next_decision: 'none')
          @activity.completed
          @activity.reload.children.count.should == 0
          @activity.status.should == :complete
        end
      end
    end
  end

  context "run sub-activity" do
    before do
      @sub_activity = {name: :import_payment, mode: :blocking, retry: 2, retry_interval: 30.seconds}
    end
    it "raises error if status is not executing" do
      expect {
        @a1.run_sub_activity(@sub_activity)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Cannot run subactivity while in status(#{@a1.status})")
    end

    it "raises error if sub-activity options are incomplete" do
      @a1.update_status!(:executing)
      expect {
        @a1.run_sub_activity({})
      }.to raise_error(WorkflowServer::InvalidParameters)
    end

    context "sub-activity is blocking" do
      it "creates and starts the sub_activity and changes the status" do
        @a1.update_status!(:executing)

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25})
        @a1.run_sub_activity(@sub_activity)
        @a1.reload.status.should == :running_sub_activity
        @a1.children.count.should == 1
        child = @a1.children.first
        child.class.should == WorkflowServer::Models::SubActivity
        child.name.should == :import_payment
        child.status.should == :executing
      end

      it "doesn't run the same sub_activity twice" do
        @a1.update_status!(:executing)

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25})
        @a1.run_sub_activity(@sub_activity.dup)
        @a1.children.count.should == 1

        @a1.update_status!(:executing)

        @a1.run_sub_activity(@sub_activity)
        @a1.children.count.should == 1
      end
    end
    context "sub-activity is non-blocking / fire_and_forget" do
      it "creates and starts the sub_activity but doesn't change status" do
        @a1.update_status!(:executing)
        @sub_activity[:mode] = :non_blocking


        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25})
        @a1.run_sub_activity(@sub_activity)
        @a1.reload.status.should == :executing
        @a1.children.count.should == 1
        child = @a1.children.first
        child.class.should == WorkflowServer::Models::SubActivity
        child.name.should == :import_payment
        child.status.should == :executing
      end
    end
  end

  context '#make_decision' do
    context 'orphan decisions = true' do
      before do
        @a1.update_attributes!(orphan_decision: true)
      end
      it "adds a decision but doesn't create the parent child relationship" do
        decisions = @wf.decisions.count

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil})
        @a1.make_decision(:test_decision, false)
        @wf.decisions.count.should == (decisions + 1)
        decision = @wf.decisions.last
        decision.parent.should be_nil
        decision.name.should == :test_decision
      end
    end

    context 'orphan decisions = false' do
      before do
        @a1.update_attributes!(orphan_decision: false)
      end
      it "calls adds an interrupt and maintains the parent child relationship" do
        decisions = @wf.decisions.count
        #TODO: guessing!
        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil})
        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :send_to_client, args: nil, max_attempts: 25})
        @a1.make_decision(:test_decision, false)
        @wf.decisions.count.should == (decisions + 1)
        decision = @wf.decisions.last
        decision.parent.should == @a1
        decision.name.should == :test_decision
      end
    end
  end

  context "#child_completed" do
    context "child was blocking" do
      it "goes back into executing state" do
        @a1.update_status!(:running_sub_activity)
        @a1.should_receive(:continue)
        @a1.child_completed(FactoryGirl.create(:sub_activity, workflow: @wf))
      end
    end
    context "child was non-blocking" do
      it "parent activity not complete" do
        @a1.should_not_receive(:continue)
        @a1.should_not_receive(:completed)
        @a1.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf))
      end

      it "parent activity completed" do
        @a1.update_attributes!(_client_done_with_activity: true)
        @a1.should_receive(:completed)
        @a1.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf))
      end
    end
  end

  context "#child_errored" do
    it "dismisses its watchdogs if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@a1)
      @a1.child_errored(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf), {:something_bad => :very_bad})
    end

    it "no changes if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_not_receive(:mass_dismiss).with(@a1)
      @a1.child_errored(FactoryGirl.create(:sub_activity, mode: :fire_and_forget, workflow: @wf), {:something_bad => :very_bad})
    end
  end

  context "#child_timeout" do
    it "dismisses its watchdogs if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@a1)
      @a1.child_timeout(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf), :something)
    end

    it "no changes if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_not_receive(:mass_dismiss).with(@a1)
      @a1.child_timeout(FactoryGirl.create(:sub_activity, mode: :fire_and_forget, workflow: @wf), :something)
    end
  end

  context "#change_status" do
    before do
      @a1.stub(:completed)
    end
    it "returns if the new status is the same as existing status" do
      expect {
        @a1.change_status(@a1.status)
      }.to_not raise_error
    end

    it "raises error if the new status field is invalid" do
      expect {
        @a1.change_status(:some_crap)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to some_crap")
    end

    context "completed" do
      it "raises error if status is not executing" do
        @a1.update_status!(:open)
        @a1.stub(:enqueue_complete_if_done)
        expect {
          @a1.change_status(:completed)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to completed")
      end

      it "raises error if next decision is invalid" do
        @a1.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])
        expect {
          @a1.change_status(:completed, {next_decision: :something_wrong, result: {a: :b, c: :d}})
        }.to raise_error(WorkflowServer::InvalidDecisionSelection, "Activity:#{@a1.name} tried to make something_wrong the next decision but is not allowed to.")
      end

      it "sets the field _client_done_with_activityd to indicate client is done with this activity" do
        @a1.update_attributes!(status: :executing)
        @a1.should_receive(:enqueue_complete_if_done)
        @a1._client_done_with_activity.should == false
        @a1.change_status(:completed)
        @a1._client_done_with_activity.should == true
      end

      it "records the next decision and result" do
        @a1.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])
        @a1.should_receive(:enqueue_complete_if_done)
        @a1.change_status(:completed, {next_decision: :more_test, result: {a: :b, c: :d}})
        @a1.reload.result.should == {"a" => :b, "c" => :d}
        @a1.reload.next_decision.should == 'more_test'
      end

      it "records none as the next decision" do
        @a1.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :complete_if_done, args: nil, max_attempts: nil})
        @a1.change_status(:completed, {next_decision: :none, result: {a: :b, c: :d}})
        @a1.reload.result.should == {"a" => :b, "c" => :d}
        @a1.reload.next_decision.should == 'none'
      end

      it "feeding the watchdog enqueues an async job to call complete_if_done" do
        @a1.update_attributes!(status: :executing, time_out: 10)
        @a1.stub(:update_attributes!)

        WorkflowServer::Models::Watchdog.should_receive(:feed).with(@a1)
        WorkflowServer::Async::Job.should_receive(:enqueue).with({event: @a1, method: :complete_if_done, args: nil, max_attempts: nil})

        @a1.change_status(:completed, {next_decision: :none, result: {a: :b, c: :d}})
      end

      it "branches raise an error if no next_decision is given" do
        a1 = FactoryGirl.create(:branch, workflow: @wf)
        a1.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])
        a1.should_not_receive(:completed)
        expect {
          a1.change_status(:completed, {result: {a: :b, c: :d}})
        }.to raise_error()
      end
    end
    context "errored" do
      it "raises error if status is not executing" do
        @a1.update_status!(:open)
        expect {
          @a1.change_status(:errored)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to errored")
      end

      it "calls errored with the error argument" do
        @a1.update_status!(:executing)
        @a1.should_receive(:errored).with({message: 100, backtrace: 200})
        @a1.change_status(:errored, {error: {message: 100, backtrace: 200}})
      end
    end
  end

  context "#errored" do
    it "retries on error" do
      @a1.update_attributes!(retry: 2, retry_interval: 40.minutes)
      @a1.errored(:some_error)
      @a1.reload.status.should == :retrying
      @a1.status_history[-2] = {"from"=>:open, "to"=>:failed, "at"=>Time.now.to_datetime.to_s, "error"=>:some_error}
      @a1.status_history[-1] = {"from"=>:failed, "to"=>:retrying, "at"=>Time.now.to_datetime.to_s}
      job = Delayed::Job.last
      job.run_at.to_s.should == (Time.now + 40.minutes).to_s
      async_job = job.payload_object
      async_job.event.should eq @a1
      async_job.method_to_call.should eq :start
    end

    it "goes into error state and calls handle_error" do
      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil})
      @a1.update_attributes!(parent: FactoryGirl.create(:decision, workflow: @wf))
      @a1.update_attributes!(retry: 2, retry_interval: 40.minutes)

      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: kind_of(WorkflowServer::Models::Activity), method: :notify_client, args: ["error", :some_error], max_attempts: 2})

      2.times do
        @a1.errored(:some_error)
        @a1.reload.status.should == :retrying
      end
      @a1.should_receive(:handle_error)
      @a1.errored(:some_error)
      @a1.reload.status.should == :error
    end
  end

  context "#handle_error" do
    before do
      @mock_decision = mock('parent_decision', name: :test)
      @a1.stub(parent_decision: @mock_decision)
    end
    it "doesn't schedule an error event if mode is fire_and_forget" do
      @a1.update_attributes!(mode: :fire_and_forget)
      @a1.should_not_receive(:parent_decision)
      @a1.__send__(:handle_error, :some_error)
    end
    it "doesn't blow up when no parent decision" do
      @a1.stub(parent_decision: nil)
      @a1.should_not_receive(:add_interrupt)
      @a1.__send__(:handle_error, :some_error)
    end
    it "adds an interrupt with the parent_decision_name_error" do
      @a1.should_receive(:add_interrupt).with(:test_error.to_s)
      @a1.__send__(:handle_error, :some_error)
    end
  end

  context "#subactivities_running?" do
    it "true when any non fire_and_forget is not in complete state" do
      child = FactoryGirl.create(:sub_activity, parent: @a1, workflow: @wf)
      @a1.__send__(:children_running?).should == true

      child.update_status!(:complete)
      @a1.__send__(:children_running?).should == false
    end

    it "false when the running subactivity is in fire_and_forget" do
      child = FactoryGirl.create(:sub_activity, parent: @a1, mode: :fire_and_forget, workflow: @wf)
      @a1.__send__(:children_running?).should == false

      child.update_attributes!(mode: :blocking)
      @a1.__send__(:children_running?).should == true
    end
  end

  context "#validate_next_decision" do
    it "raises an exception if the next decision is not in the list of valid options and 'any' is not present" do
      expect{@a1.validate_next_decision('super_bad_decision')}.to raise_error(WorkflowServer::InvalidDecisionSelection, 'Activity:make_initial_payment tried to make super_bad_decision the next decision but is not allowed to.')
    end
    it "does not raise an exception if the next decision is not in the list of valid options" do
      @a1.valid_next_decisions << 'super_bad_decision'
      expect{@a1.validate_next_decision('super_bad_decision')}.to_not raise_error
    end
    it "does not raise an exception if 'any' is present" do
      @a1.valid_next_decisions << 'any'
      expect{@a1.validate_next_decision('super_bad_decision')}.to_not raise_error
    end
  end
end
