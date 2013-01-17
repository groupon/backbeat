require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Activity do
  before do
    @event_klass = WorkflowServer::Models::Activity
    @wf = FactoryGirl.create(:workflow)
    @a1 = FactoryGirl.create(:activity, workflow: @wf).reload
  end
  it_should_behave_like 'events'

  it "activities cannot be blocking and always" do
    expect {
      WorkflowServer::Models::Activity.create!(name: :some_activity, mode: :blocking, always: true)
    }.to raise_error(Mongoid::Errors::Validations)
  end

  context "#start" do
    it "calls perform_activity and goes into executing state" do
      WorkflowServer::AsyncClient.should_receive(:perform_activity).with(@a1)
      @a1.start
      @a1.status.should == :executing
    end
  end

  context "on complete" do
    context "subactivities running" do
      it "sets the status to waiting_for_sub_activities" do
        @a1.stub(subactivities_running?: true)
        @a1.completed
        @a1.status.should == :waiting_for_sub_activities
      end
    end
    context "no subactivities running" do
      before do
        @a1.stub(subactivities_running?: false)
      end
      context "parent is not a decision" do
        it "goes to complete state - no decision task scheduled" do
          @a1.completed(:decision_blah_blah)
          @a1.reload.children.count.should == 0
          @a1.status.should == :complete
        end
      end
      context "parent is a decision" do
        before do
          @activity = FactoryGirl.create(:activity, parent: FactoryGirl.create(:decision), workflow: @wf)
        end
        context "next decision is set" do
          it "raises an error if invalid next decision is given" do
            expect {
              @activity.completed(:decision_blah_blah)
            }.to raise_error(WorkflowServer::InvalidDecisionSelection, "activity:#{@activity.name} tried to make decision_blah_blah the next decision but is not allowed to.")
          end
          it "schedules a decision task and goes to complete state" do
            @activity.update_attributes!(valid_next_decisions: [:decision_blah_blah])
            @activity.completed(:decision_blah_blah)
            @activity.reload.children.count.should == 1
            decision = @activity.children.first
            decision.name.should == :decision_blah_blah
            @activity.status.should == :complete
          end
        end
        context "next decision is nil" do
          it "schedules a activity_succeeded decision" do
            @activity.completed(nil)
            @activity.reload.children.count.should == 1
            decision = @activity.children.first
            decision.name.should == "#{@activity.name}_succeeded".to_sym
            @activity.status.should == :complete
          end
        end
        context "next decision is :none" do
          it "no decision event scheduled" do
            @activity.completed(:none)
            @activity.reload.children.count.should == 0
            @activity.status.should == :complete
          end
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

  context "#child_completed" do
    context "child was blocking" do
      it "goes back into executing state" do
        @a1.update_status!(:running_sub_activity)
        @a1.should_receive(:continue)
        @a1.child_completed(FactoryGirl.create(:sub_activity))
      end
    end
    context "child was non-blocking" do
      it "parent activity not complete" do
        @a1.should_not_receive(:continue)
        @a1.should_not_receive(:completed)
        @a1.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking))
      end
      it "parent activity completed" do
        @a1.update_status!(:waiting_for_sub_activities)
        @a1.should_receive(:completed)
        @a1.child_completed(FactoryGirl.create(:sub_activity, mode: :non_blocking))
      end
    end
  end

  context "#child_errored" do
    it "goes in error state if child wasn't fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      @a1.child_errored(FactoryGirl.create(:sub_activity, mode: :non_blocking), {:something_bad => :very_bad})
      @a1.status.should == :error
      @a1.status_history.last.should == {from: :open, to: :error, at: Time.now.to_datetime.to_s, error: {:something_bad=>:very_bad}}
    end
    it "no changes if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      @a1.child_errored(FactoryGirl.create(:sub_activity, mode: :fire_and_forget), {:something_bad => :very_bad})
      @a1.status.should_not == :error
    end
  end

  context "#child_timeout" do
    it "goes in error state if child wasn't fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      @a1.child_timeout(FactoryGirl.create(:sub_activity, mode: :non_blocking), :something)
      @a1.status.should == :timeout
      @a1.status_history.last.should == {from: :open, to: :timeout, at: Time.now.to_datetime.to_s, error: :something}
    end
    it "no changes if child was fire_and_forget" do
      @a1.update_attributes!(retry: 0)
      @a1.child_timeout(FactoryGirl.create(:sub_activity, mode: :fire_and_forget), :something)
      @a1.status.should_not == :timeout
    end
  end

  context "#change_status" do
    it "returns if the new status is the same as existing status" do
      expect {
        @a1.change_status(@a1.status)
      }.to_not raise_error
    end
    it "raises error if the new status field is invalid" do
      expect {
        @a1.change_status(:some_crap)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Invalid status some_crap")
    end
    context "completed" do
      it "raises error if status is not executing" do
        @a1.update_status!(:open)
        expect {
          @a1.change_status(:completed)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Activity make_initial_payment can't transition from open to completed")
      end
      it "calls completed with the next decision" do
        @a1.update_status!(:executing)
        @a1.should_receive(:completed).with(:none)
        @a1.change_status(:completed, {next_decision: :none})
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
      handler = YAML.load(job.handler)
      handler.should == @a1
    end
    it "goes into error state andd puts a decision task" do
      @a1.update_attributes!(parent: FactoryGirl.create(:decision))
      @a1.update_attributes!(retry: 2, retry_interval: 40.minutes)
      2.times do
        @a1.errored(:some_error)
        @a1.reload.status.should == :retrying
      end
      @a1.errored(:some_error)
      @a1.reload.status.should == :error
      @a1.reload.children.count.should == 1
      dec = @a1.children.first
      dec.name.should == "#{@a1.name}_errored".to_sym
    end
  end

  context "#subactivities_running?" do
    it "true when any non fire_and_forget is not in complete state" do
      child = FactoryGirl.create(:sub_activity, parent: @a1)
      @a1.__send__(:subactivities_running?).should == true

      child.update_status!(:complete)
      @a1.__send__(:subactivities_running?).should == false
    end

    it "false when the running subactivity is in fire_and_forget" do
      child = FactoryGirl.create(:sub_activity, parent: @a1, mode: :fire_and_forget)
      @a1.__send__(:subactivities_running?).should == false

      child.update_attributes!(mode: :blocking)
      @a1.__send__(:subactivities_running?).should == true
    end
  end
end