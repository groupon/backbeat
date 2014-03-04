require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Activity do
  let(:user) { FactoryGirl.create(:user) }

  before do
    @event_klass = WorkflowServer::Models::Activity
    @wf = FactoryGirl.create(:workflow, user: user)
    @event = FactoryGirl.create(:activity, workflow: @wf)
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
        .with({event: @event, method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
      @event.start
      @event.status.should == :executing
    end
  end

  context "#restart" do
    it "updates status to :restarting before calling start" do
      @event.update_status!(:timeout)
      @event.should_receive(:update_status!).with(:restarting)
      @event.should_receive(:start).and_raise

      expect{@event.restart}.to raise_error
    end

    it "calls start" do
      @event.update_status!(:timeout)
      @event.should_receive(:start)

      @event.restart
    end

    it "raises an error if the current status is not either :error or :timeout" do
      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: @event, method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
        .exactly(2).times

      @event.update_status!(:open)
      expect {
        @event.restart
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to restarting")

      @event.update_status!(:error)
      expect {
        @event.restart
      }.to_not raise_error

      @event.update_status!(:timeout)
      expect {
        @event.restart
      }.to_not raise_error
    end
  end

  context '#resumed' do
    it 'calls send_to_client' do
      @event.should_receive(:send_to_client)
      @event.resumed
    end
  end

  context '#child_resumed' do
    context 'child is fire_and_forget' do
      it 'no-op' do
        @event.update_attributes!(time_out: 10)
        a2 = FactoryGirl.create(:activity, mode: :fire_and_forget, parent: @event, workflow: @wf)
        WorkflowServer::Models::Watchdog.should_not_receive(:start)
        @event.child_resumed(a2)
      end
    end
    context 'child is not fire_and_forget' do
      it 'no-op' do
        @event.update_attributes!(time_out: 10)
        a2 = FactoryGirl.create(:activity, mode: :non_blocking, parent: @event, workflow: @wf)
        #WorkflowServer::Models::Watchdog.should_receive(:start).with(@event, :timeout, 10)
        @event.child_resumed(a2)
      end
    end
  end

  context "#send_to_client" do
    before do
      @event.update_attributes!(time_out: 10)
    end
    context 'workflow is paused' do
      before do
        @wf.update_status!(:pause)
      end
      it 'puts itself in paused state and doesn\'t go to client' do
        WorkflowServer::Client.should_not_receive(:perform_activity)
        WorkflowServer::Models::Watchdog.should_not_receive(:start)
        @event.send(:send_to_client)
        @event.status.should == :pause
      end
    end
    context 'workflow is not paused' do
      it "calls out to workflow async client to perform activity" do
        WorkflowServer::Client.should_receive(:perform_activity).with(@event)
        #WorkflowServer::Models::Watchdog.should_receive(:start).with(@event, :timeout, 10)
        @event.send(:send_to_client)
        @event.status.should == :executing
      end
    end
  end

  context "on complete" do
    context "no subactivities running" do
      before do
        @event.stub(subactivities_running?: false)
        @activity = FactoryGirl.create(:activity, parent: FactoryGirl.create(:decision, workflow: @wf), workflow: @wf)
      end

      context "next decision is set" do
        it "schedules a decision task and goes to complete state" do
          @activity.update_attributes!(next_decision: :decision_blah_blah)

          WorkflowServer::Async::Job.should_receive(:enqueue)
            .with({event: kind_of(WorkflowServer::Models::Decision), method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
          WorkflowServer::Async::Job.should_receive(:enqueue)
            .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil}, kind_of(Time))
          WorkflowServer::Async::Job.should_receive(:enqueue)
            .with({event: @activity.parent, method: :child_completed, args: [@activity.id], max_attempts: nil}, kind_of(Time))

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
        @event.run_sub_activity(@sub_activity)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Cannot run subactivity while in status(#{@event.status})")
    end

    it "raises error if sub-activity options are incomplete" do
      @event.update_status!(:executing)
      expect {
        @event.run_sub_activity({})
      }.to raise_error(WorkflowServer::InvalidParameters)
    end

    context "sub-activity is blocking" do
      it "creates and starts the sub_activity and changes the status" do
        @event.update_status!(:executing)

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
        @event.run_sub_activity(@sub_activity)
        @event.reload.status.should == :running_sub_activity
        @event.children.count.should == 1
        child = @event.children.first
        child.class.should == WorkflowServer::Models::SubActivity
        child.name.should == :import_payment
        child.status.should == :executing
      end

      it "doesn't run the same sub_activity twice" do
        @event.update_status!(:executing)

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
        @event.run_sub_activity(@sub_activity.dup)
        @event.children.count.should == 1

        @event.update_status!(:executing)

        @event.run_sub_activity(@sub_activity)
        @event.children.count.should == 1
      end
    end
    context "sub-activity is non-blocking / fire_and_forget" do
      it "creates and starts the sub_activity but doesn't change status" do
        @event.update_status!(:executing)
        @sub_activity[:mode] = :non_blocking


        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
        @event.run_sub_activity(@sub_activity)
        @event.reload.status.should == :executing
        @event.children.count.should == 1
        child = @event.children.first
        child.class.should == WorkflowServer::Models::SubActivity
        child.name.should == :import_payment
        child.status.should == :executing
      end
    end
  end

  context '#make_decision' do
    context 'orphan decisions = true' do
      before do
        @event.update_attributes!(orphan_decision: true)
      end
      it "adds a decision but doesn't create the parent child relationship" do
        decisions = @wf.decisions.count

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil}, kind_of(Time))
        @event.make_decision(:test_decision, false)
        @wf.decisions.count.should == (decisions + 1)
        decision = @wf.decisions.last
        decision.parent.should be_nil
        decision.name.should == :test_decision
      end
    end

    context 'orphan decisions = false' do
      before do
        @event.update_attributes!(orphan_decision: false)
      end
      it "calls adds an interrupt and maintains the parent child relationship" do
        decisions = @wf.decisions.count
        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil}, kind_of(Time))
        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Decision), method: :send_to_client, args: nil, max_attempts: 25}, kind_of(Time))
        @event.make_decision(:test_decision, false)
        @wf.decisions.count.should == (decisions + 1)
        decision = @wf.decisions.last
        decision.parent.should == @event
        decision.name.should == :test_decision
      end
    end
  end

  context "#child_completed" do
    context "child was blocking" do
      it "goes back into executing state" do
        @event.update_status!(:running_sub_activity)
        @event.should_receive(:continue)
        @event.child_completed(FactoryGirl.create(:sub_activity, workflow: @wf).id)
      end
    end
    context "child was non-blocking" do
      it "parent activity not complete" do
        @event.should_not_receive(:continue)
        @event.should_not_receive(:completed)
        @event.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf))
      end

      it "parent activity completed" do
        @event.update_attributes!(_client_done_with_activity: true)
        @event.should_receive(:completed)
        @event.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf))
      end
    end
  end

  context "#child_errored" do
    it "dismisses its watchdogs if child was fire_and_forget" do
      @event.update_attributes!(retry: 0)
      #WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@event)
      @event.child_errored(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf), {:something_bad => :very_bad})
    end

    it "no changes if child was fire_and_forget" do
      @event.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_not_receive(:mass_dismiss).with(@event)

      @event.child_errored(FactoryGirl.create(:sub_activity, mode: :fire_and_forget, workflow: @wf), {:something_bad => :very_bad})
    end
  end

  context "#child_timeout" do
    it "dismisses its watchdogs if child was fire_and_forget" do
      @event.update_attributes!(retry: 0)
      #WorkflowServer::Models::Watchdog.should_receive(:mass_dismiss).with(@event)
      @event.child_timeout(FactoryGirl.create(:sub_activity, mode: :non_blocking, workflow: @wf), :something)
    end

    it "no changes if child was fire_and_forget" do
      @event.update_attributes!(retry: 0)
      WorkflowServer::Models::Watchdog.should_not_receive(:mass_dismiss).with(@event)
      @event.child_timeout(FactoryGirl.create(:sub_activity, mode: :fire_and_forget, workflow: @wf), :something)
    end
  end

  context "#change_status" do
    before do
      @event.stub(:completed)
    end
    it "returns if the new status is the same as existing status" do
      expect {
        @event.change_status(@event.status)
      }.to_not raise_error
    end

    it "raises error if the new status field is invalid" do
      expect {
        @event.change_status(:some_crap)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to some_crap")
    end

    context 'resolved' do
      it 'calls resolved' do
        @event.should_receive(:resolved)

        @event.change_status(:resolved)
      end
    end

    context "completed" do
      it "raises error if status is not executing" do
        @event.update_status!(:open)
        @event.stub(:enqueue_complete_if_done)
        expect {
          @event.change_status(:completed)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to completed")
      end

      it "raises error if next decision is invalid" do
        @event.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])
        expect {
          @event.change_status(:completed, {next_decision: :something_wrong, result: {a: :b, c: :d}})
        }.to raise_error(WorkflowServer::InvalidDecisionSelection, "Activity:#{@event.name} tried to make something_wrong the next decision but is not allowed to.")
      end

      it "sets the field _client_done_with_activityd to indicate client is done with this activity" do
        @event.update_attributes!(status: :executing)
        @event.should_receive(:enqueue_complete_if_done)
        @event._client_done_with_activity.should == false
        @event.change_status(:completed)
        @event._client_done_with_activity.should == true
      end

      it "records the next decision and result" do
        @event.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])
        @event.should_receive(:enqueue_complete_if_done)
        @event.change_status(:completed, {next_decision: :more_test, result: {a: :b, c: :d}})
        @event.reload.result.should == {"a" => :b, "c" => :d}
        @event.reload.next_decision.should == 'more_test'
      end

      it "records none as the next decision" do
        @event.update_attributes!(status: :executing, valid_next_decisions: ['test', 'more_test'])

        WorkflowServer::Async::Job.should_receive(:enqueue)
          .with({event: kind_of(WorkflowServer::Models::Activity), method: :complete_if_done, args: nil, max_attempts: nil}, kind_of(Time))
        @event.change_status(:completed, {next_decision: :none, result: {a: :b, c: :d}})
        @event.reload.result.should == {"a" => :b, "c" => :d}
        @event.reload.next_decision.should == 'none'
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
        @event.update_status!(:open)
        expect {
          @event.change_status(:errored)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to errored")
      end

      it "calls errored with the error argument" do
        @event.update_status!(:executing)
        @event.should_receive(:enqueue_errored).with(args: [{message: 100, backtrace: 200}])
        @event.change_status(:errored, {error: {message: 100, backtrace: 200}})
      end
    end
  end

  context "#errored" do
    it "retries on error" do
      @event.update_attributes!(retry: 2, retry_interval: 40.minutes)
      @event.errored(:some_error)
      @event.reload.status.should == :retrying
      @event.status_history[-2] = {"from"=>:open, "to"=>:failed, "at"=>Time.now.to_datetime.to_s, "error"=>:some_error}
      @event.status_history[-1] = {"from"=>:failed, "to"=>:retrying, "at"=>Time.now.to_datetime.to_s}
      job = Delayed::Job.last
      job.run_at.to_s.should == (Time.now.utc + 40.minutes).to_s
      async_job = job.payload_object
      async_job.event.should eq @event
      async_job.method_to_call.should eq :start
    end

    it "goes into error state and calls handle_error" do
      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: kind_of(WorkflowServer::Models::Decision), method: :schedule_next_decision, args: nil, max_attempts: nil}, kind_of(Time))
      @event.update_attributes!(parent: FactoryGirl.create(:decision, workflow: @wf))
      @event.update_attributes!(retry: 2, retry_interval: 40.minutes)

      WorkflowServer::Async::Job.should_receive(:enqueue)
        .with({event: kind_of(WorkflowServer::Models::Activity), method: :notify_client, args: ["error", :some_error], max_attempts: 2}, kind_of(Time))

      2.times do
        @event.errored(:some_error)
        @event.reload.status.should == :retrying
      end
      @event.should_receive(:handle_error)
      @event.errored(:some_error)
      @event.reload.status.should == :error
    end
  end

  context "#handle_error" do
    before do
      @mock_decision = double('parent_decision', name: :test)
      @event.stub(parent_decision: @mock_decision)
    end
    it "doesn't schedule an error event if mode is fire_and_forget" do
      @event.update_attributes!(mode: :fire_and_forget)
      @event.should_not_receive(:parent_decision)
      @event.__send__(:handle_error, :some_error)
    end
    it "doesn't blow up when no parent decision" do
      @event.stub(parent_decision: nil)
      @event.should_not_receive(:add_interrupt)
      @event.__send__(:handle_error, :some_error)
    end
    it "adds an interrupt with the parent_decision_name_error" do
      @event.should_receive(:add_interrupt).with(:test_error.to_s)
      @event.__send__(:handle_error, :some_error)
    end
  end

  context "#subactivities_running?" do
    it "true when any non fire_and_forget is not in complete state" do
      child = FactoryGirl.create(:sub_activity, parent: @event, workflow: @wf)
      @event.__send__(:children_running?).should == true

      child.update_status!(:complete)
      @event.__send__(:children_running?).should == false
    end

    it "false when the running subactivity is in fire_and_forget" do
      child = FactoryGirl.create(:sub_activity, parent: @event, mode: :fire_and_forget, workflow: @wf)
      @event.__send__(:children_running?).should == false

      child.update_attributes!(mode: :blocking)
      @event.__send__(:children_running?).should == true
    end
  end

  context "#validate_next_decision" do
    it "raises an exception if the next decision is not in the list of valid options and 'any' is not present" do
      expect{@event.validate_next_decision('super_bad_decision')}.to raise_error(WorkflowServer::InvalidDecisionSelection, 'Activity:make_initial_payment tried to make super_bad_decision the next decision but is not allowed to.')
    end
    it "does not raise an exception if the next decision is not in the list of valid options" do
      @event.valid_next_decisions << 'super_bad_decision'
      expect{@event.validate_next_decision('super_bad_decision')}.to_not raise_error
    end
    it "does not raise an exception if 'any' is present" do
      @event.valid_next_decisions << 'any'
      expect{@event.validate_next_decision('super_bad_decision')}.to_not raise_error
    end
  end
end
