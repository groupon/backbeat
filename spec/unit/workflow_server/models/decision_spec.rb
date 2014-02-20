require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Decision do
  let(:user) { FactoryGirl.create(:user) }

  before do
    @event_klass = WorkflowServer::Models::Decision
    @event_data = {name: :test_decision, user: user, workflow: FactoryGirl.create(:workflow, user: user)}
    @wf = FactoryGirl.create(:workflow, user: user)
    @event = FactoryGirl.create(:decision, workflow: @wf, name: "WF_Decision-1")
  end

  it_should_behave_like 'events'

  it "calls schedule next decision on create" do
    decision = WorkflowServer::Models::Decision.new(@event_data)
    decision.should_receive(:enqueue_schedule_next_decision)
    decision.save!
  end

  context "#start" do
    it "schedules an async job to call out to the client and changes status to enqueued" do
      WebMock.stub_request(:post, "http://localhost:9000/decision").
               to_return(:status => 200, :body => "", :headers => {})

      @event.start
      @event.status.should == :sent_to_client

      @event.status.should == :sent_to_client
    end
  end

  context "#restart" do
    it "calls start" do
      @event.update_status!(:timeout)

      @event.should_receive(:start)

      @event.restart
    end

    it "updates status to :restarting before calling start" do
      @event.update_status!(:timeout)

      @event.should_receive(:update_status!).with(:restarting)
      @event.should_receive(:start).and_raise

      expect{@event.restart}.to raise_error
    end

    it "raises an error if the current status is not either :errored or :timeout" do
      @event.update_status!(:open)
      expect {
        @event.restart
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Decision WF_Decision-1 can't transition from open to restarting")

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

  context "#send_to_client" do
    context 'workflow is paused' do
      before do
        @wf.update_status!(:pause)
      end
      it 'puts itself in paused state and doesn\'t go to client' do
        WorkflowServer::Client.should_not_receive(:make_decision)
        @event.send(:send_to_client)
        @event.status.should == :pause
      end
    end
    context 'workflow is not paused' do
      it "calls out to workflow async client to perform activity" do
        WorkflowServer::Client.should_receive(:make_decision).with(@event)
        #WorkflowServer::Models::Watchdog.should_receive(:start).with(@event, :decision_deciding_time_out, 12.hours)
        @event.send(:send_to_client)
        @event.status.should == :sent_to_client
      end
      context 'on error' do
        it 'dismisses the watchdog and re-raises the error' do
          #WorkflowServer::Models::Watchdog.should_receive(:start).with(@event, :decision_deciding_time_out, 12.hours)
          WorkflowServer::Client.stub(:make_decision).and_raise('some error')
          #WorkflowServer::Models::Watchdog.should_receive(:dismiss).with(@event, :decision_deciding_time_out)
          expect {
            @event.send(:send_to_client)
          }.to raise_error("some error")
        end
      end
    end
  end

  context 'resolved' do
    it 'calls resolved' do
      @event.should_receive(:resolved)

      @event.change_status(:resolved)
    end
  end

  context "#completed" do
    it "calls enqueue_schedule_next_decision to schedule the next decision" do
      @event.should_receive(:enqueue_schedule_next_decision)
      @event.completed
    end
  end

  context "#child_completed" do
    it "calls refresh if child is Activity, Branch or Workflow" do
      [:activity, :workflow].each do |child|
        options = {parent: @event, workflow: @wf}
        options[:user] = user if child == :workflow
        child = FactoryGirl.create(child, options)
        @event.should_receive(:continue)
        @event.child_completed(child.id)
      end
      [:flag, :signal].each do |child|
        child = FactoryGirl.create(child, parent: @event, workflow: @wf)
        @event.should_not_receive(:continue)
        @event.should_receive(:complete_if_done)
        @event.child_completed(child.id)
      end
    end
  end

  context "#change_status" do
    it "returns if the new status is the same as existing status" do
      expect {
        @event.change_status(@event.status)
      }.to_not raise_error
    end
    it "raises error if the new status field is invalid" do
      expect {
        @event.change_status(:some_crap)
      }.to raise_error(WorkflowServer::InvalidEventStatus, "Invalid status some_crap")
    end
    context "deciding" do
      it "raises error unless status is enqueued" do
        @event.update_status!(:open)
        expect {
          @event.change_status(:deciding)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Decision WF_Decision-1 can't transition from open to deciding")
      end
      it "puts the decision in deciding state" do
        @event.update_status!(:sent_to_client)
        @event.reload
        @event.change_status(:deciding)
        @event.status.should == :deciding
      end
    end
    context "#deciding_complete" do
      it "raises error unless status is enqueued / deciding" do
        @event.update_status!(:open)
        expect {
          @event.change_status(:deciding_complete)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Decision WF_Decision-1 can't transition from open to deciding_complete")
      end

      [:sent_to_client, :deciding].each do |base_state|
        it "puts the decision in completed state when no decisions" do
          @event.update_status!(base_state)
          @event.change_status(:deciding_complete)
          @event.async_jobs.map(&:payload_object).map(&:perform)
          WorkflowServer::Workers::SidekiqJobWorker.drain
          @event.reload
          @event.status.should == :complete
        end
      end

      it "puts the decision in executing state and starts the first action" do
        @event.update_status!(:deciding)
        decisions = [
          {type: :flag, name: :wFlag},
          {type: :activity, name: :make_initial_payment, actor_klass: "LineItem", actor_id: 100, retry: 100, retry_interval: 5},
          {type: :branch, name: :make_initial_payment_branch, actor_id: 100, retry: 100, retry_interval: 5},
          {type: :workflow, name: :some_name, workflow_type: :error_recovery_workflow, subject: {subject_klass: "PaymentTerm", subject_id: 1000}, decider: "ErrorDecider"},
          {type: :complete_workflow},
          {type: :timer, name: :wTimer, fires_at: Time.now + 1000.seconds}
        ]
        WebMock.stub_request(:post, "http://localhost:9000/activity").
        to_return(:status => 200, :body => "", :headers => {})

        run_async_jobs do
          @event.add_decisions(decisions)
          @event.change_status(:deciding_complete)
        end

        @event.reload
        @event.children.any_in(_type: [WorkflowServer::Models::Flag]).first.status.should == :complete
        @event.children.any_in(_type: [WorkflowServer::Models::Activity]).first.status.should == :executing
        @event.children.any_in(_type: [WorkflowServer::Models::Branch, WorkflowServer::Models::Workflow, WorkflowServer::Models::WorkflowCompleteFlag, WorkflowServer::Models::Timer]).each do |child|
          child.status.should == :open
        end
        @event.status.should == :executing
      end
    end
    context "#errored" do
      it "raises error unless status is enqueued / deciding" do
        @event.update_status!(:open)
        expect {
          @event.change_status(:errored)
        }.to raise_error(WorkflowServer::InvalidEventStatus, "Decision WF_Decision-1 can't transition from open to errored")
      end
      [:sent_to_client, :deciding].each do |base_state|
        it "puts the decision in error state and records the error - #{base_state}" do
          @event.update_status!(base_state)
          @event.change_status(:errored, error: {something: :bad_happened})
          @event.reload
          @event.status.should == :error
          @event.status_history.last.should == {"from"=>base_state, "to"=>:error, "tid" => nil, "at"=>Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L'), "error"=>{"something"=>:bad_happened}}
        end
      end
    end
  end

  # context "#child_errored" do
  #   it "goes in error state" do
  #     @event.status.should_not == :error
  #     @event.child_errored(FactoryGirl.create(:flag), {something: :bad_happened})
  #     @event.status.should == :error
  #     @event.status_history.last.should == {from: :enqueued, to: :error, at: Time.now.to_datetime.to_s, error: {something: :bad_happened}}
  #   end
  # end
  # 
  # context "#child_timeout" do
  #   it "goes in timeout state" do
  #     @event.status.should_not == :timeout
  #     @event.child_timeout(FactoryGirl.create(:flag), {something: :timed_out})
  #     @event.status.should == :timeout
  #     @event.status_history.last.should == {from: :enqueued, to: :timeout, at: Time.now.to_datetime.to_s, error: {something: :timed_out}}
  #   end
  # end

  context "#start_next_action" do
    it "keeps starting the next actions till it hits a blocking action" do
      a1 = FactoryGirl.create(:activity, parent: @event, workflow: @wf)
      a2 = FactoryGirl.create(:branch, mode: :non_blocking, parent: @event, workflow: @wf)
      a3 = FactoryGirl.create(:activity, parent: @event, workflow: @wf)
      a4 = FactoryGirl.create(:flag, parent: @event, workflow: @wf)
      @event.reload
      @event.__send__ :start_next_action
      WorkflowServer::Workers::SidekiqJobWorker.drain
      a1.reload.status.should == :executing
      a2.reload.status.should == :open
      a3.reload.status.should == :open
      a4.reload.status.should == :open

      # simulate a1 is done
      a1.completed
      WorkflowServer::Workers::SidekiqJobWorker.drain
      a1.reload.status.should == :complete
      a2.reload.status.should == :executing
      a3.reload.status.should == :executing
      a4.reload.status.should == :open
    end
  end

  context "#open_events" do
    it "yields on each open payment" do
      a1 = FactoryGirl.create(:activity, parent: @event, workflow: @wf)
      a2 = FactoryGirl.create(:branch, mode: :non_blocking, parent: @event, workflow: @wf)
      collected= []
      @event.__send__(:open_events) do |event|
        collected << event
      end
      collected.should include(a1)
      collected.should include(a2)
    end
  end

  context "#any_incomplete_blocking_activities_branches_or_workflows?" do
    [:activity, :branch, :workflow].each do |event|
      it "returns true if any blocking #{event} is executing" do
        options = {parent: @event, workflow: @wf}
        options[:user] = user if event == :workflow
        child = FactoryGirl.create(event, options)
        @event.__send__(:any_incomplete_blocking_activities_branches_or_workflows?).should == false
        child.update_status!(:executing)
        @event.__send__(:any_incomplete_blocking_activities_branches_or_workflows?).should == true
        child.update_status!(:complete)
        @event.__send__(:any_incomplete_blocking_activities_branches_or_workflows?).should == false
      end
    end
  end

  context "#all_children_done?" do
    [:activity, :branch, :workflow, :flag, :signal, :timer].each do |event|
      it "false when any child in open state" do
        options = {parent: @event, workflow: @wf}
        options[:user] = user if event == :workflow
        child = FactoryGirl.create(event, options)
        @event.__send__(:all_children_done?).should == false
      end
    end

    [:activity, :branch, :workflow, :flag].each do |event|
      it "returns true when all non-fire and forget #{event} are completed" do
        options = {parent: @event, workflow: @wf}
        options[:user] = user if event == :workflow
        child = FactoryGirl.create(event, options)
        @event.__send__(:all_children_done?).should == false
        child.update_attributes!(mode: :fire_and_forget, status: :open)
        @event.__send__(:all_children_done?).should == false
        child.update_attributes!(mode: :fire_and_forget, status: :executing)
        @event.__send__(:all_children_done?).should == true
        child.update_attributes!(mode: :blocking)
        @event.__send__(:all_children_done?).should == false
        child.update_attributes!(status: :complete)
        @event.__send__(:all_children_done?).should == true
      end
    end
    context '#signal' do
      it "returns false if signal is open or executing" do
        child = FactoryGirl.create(:signal, {parent: @event, workflow: @wf})
        child.update_status!(:executing)
        @event.__send__(:all_children_done?).should == false
        child.update_attributes!(mode: :fire_and_forget)
        @event.__send__(:all_children_done?).should == true
      end
    end
    context "#timer" do
      it "returns false if any timer is open" do
        child = FactoryGirl.create(:timer, {parent: @event, workflow: @wf})
        @event.__send__(:all_children_done?).should == false
      end
      [:executing, :fired, :complete].each do |status|
        it "returns true if timer is in state #{status}" do
          child = FactoryGirl.create(:timer, {parent: @event, workflow: @wf})
          child.update_status!(status)
          @event.__send__(:all_children_done?).should == true
        end
      end
      context '#blocking timer' do
        before do
          @child = FactoryGirl.create(:timer, {parent: @event, workflow: @wf, mode: :blocking})
        end
        [:open, :scheduled, :executing, :fired].each do |state|
          it "returns false if timer is in state=#{state}" do
            @child.update_attributes!(status: state)
            @event.__send__(:all_children_done?).should == false
          end
        end
        it "returns false when timer is complete" do
          @child.update_attributes!(status: :complete)
          @event.__send__(:all_children_done?).should == true
        end
      end
    end
  end
end
