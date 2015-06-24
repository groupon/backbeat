require "spec_helper"
require "migration/migrate_workflow"

describe Migration::MigrateWorkflow, v2: true do
  let(:v1_user) { FactoryGirl.create(:v1_user) }
  let(:v1_workflow) { FactoryGirl.create(:workflow, user: v1_user) }
  let(:v1_signal) { FactoryGirl.create(:signal, parent: nil, workflow: v1_workflow, status: :complete) }

  let(:v2_user) { FactoryGirl.create(:v2_user, id: v1_user.id) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow, user: v2_user) }

  context ".queue_conversion_batch" do
    it "queues a batch of workflow ids to the conversion worker" do
      FactoryGirl.create(:workflow, user: v1_user)
      10.times do |i|
        FactoryGirl.create(
          :workflow,
          name: "Workflow #{i}",
          workflow_type: :international,
          user: v1_user,
          status: :complete
        )
      end

      Migration.queue_conversion_batch(types: [:international])

      expect(Migration::Workers::Migrator.jobs.count).to eq(10)
    end

    it "respects the provided limit" do
      3.times do |i|
        FactoryGirl.create(
          :workflow,
          name: "Workflow #{i}",
          workflow_type: :international,
          user: v1_user,
          status: :complete
        )
      end

      Migration.queue_conversion_batch(limit: 2, types: [:international])

      expect(Migration::Workers::Migrator.jobs.count).to eq(2)
    end

    it "does not migrate workflows that have already been migrated" do
      FactoryGirl.create(
        :workflow,
        name: "Workflow",
        workflow_type: :international,
        user: v1_user,
        migrated: true,
        status: :complete
      )

      Migration.queue_conversion_batch(limit: 2, types: [:international])

      expect(Migration::Workers::Migrator.jobs.count).to eq(0)
    end
  end

  context ".find_or_create_v2_workflow" do
    it "returns v2 workflow if it already exists" do
      FactoryGirl.create(:v2_workflow, name: "wrong workflow", user: v2_user)
      v2_workflow = FactoryGirl.create(:v2_workflow, id: v1_workflow.id, user: v2_user)
      workflow = Migration::MigrateWorkflow.find_or_create_v2_workflow(v1_workflow)

      expect(workflow.class.to_s).to eq("V2::Workflow")
      expect(workflow.id).to eq(v2_workflow.id)
    end

    it "creates v2 workflow if it does not exists" do
      v2_user
      expect(V2::Workflow.count).to eq(0)

      workflow = Migration::MigrateWorkflow.find_or_create_v2_workflow(v1_workflow)

      expect(V2::Workflow.count).to eq(1)
      expect(workflow.name).to eq(v1_workflow.name)
      expect(workflow.complete).to eq(false)
      expect(workflow.decider).to eq(v1_workflow.decider)
      expect(workflow.subject).to eq(v1_workflow.subject)
      expect(workflow.id).to eq(v1_workflow.id)
      expect(workflow.user_id).to eq(v2_user.id)
    end
  end

  it "marks both v2 and v2 workflows as migrated" do
    expect(v1_workflow.migrated).to eq(false)
    expect(v2_workflow.migrated).to eq(false)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

    expect(v1_workflow.migrated).to eq(true)
    expect(v2_workflow.migrated).to eq(true)
  end

  it "migrates v1 signals to v2 decisions" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_decision = v2_workflow.children.first

    expect(v2_decision.id).to eq(v1_decision.id)
    expect(v2_decision.mode).to eq("blocking")
    expect(v2_decision.name).to eq(v1_decision.name.to_s)
    expect(v2_decision.parent).to eq(v2_workflow)
    expect(v2_decision.user_id).to eq(v2_user.id)
    expect(v2_decision.legacy_type).to eq("decision")
  end

  it "marks the v1 workflow as migrated" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

    expect(v1_workflow.reload.migrated?).to eq(true)
  end

  it "returns if workflow is already migrated" do
    v2_workflow.update_attributes!(migrated: true)
    expect(v1_workflow).to_not receive(:get_children)
    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow.reload)
  end

  it "migrates great plains style workflow" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
    v1_activity = FactoryGirl.create(:activity, parent: v1_decision, workflow: v1_workflow, status: :complete)
    v1_sub_activity = FactoryGirl.create(:activity, parent: v1_activity, workflow: v1_workflow, status: :complete)
    v1_sub_decision = FactoryGirl.create(:decision, parent: v1_activity, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)
    v2_decision = v2_workflow.children.first
    v2_activity = v2_decision.children.first

    expect(v2_decision.children.count).to eq(1)
    expect(v2_activity.children.count).to eq(2)

    sub_activity = v2_activity.children.first

    expect(sub_activity.name).to eq(v1_sub_activity.name.to_s)
    expect(sub_activity.id).to eq(v1_sub_activity.id)
    expect(sub_activity.legacy_type).to eq("activity")

    sub_decision = v2_activity.children.second
    expect(sub_decision.name).to eq(v1_sub_decision.name.to_s)
    expect(sub_decision.id).to eq(v1_sub_decision.id)
    expect(sub_decision.legacy_type).to eq("decision")
    expect(v1_workflow.reload.migrated?).to eq(true)
  end

  it "migrates workflow with nested timers" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
    v1_timer = FactoryGirl.create(
      :timer,
      parent: v1_decision,
      workflow: v1_workflow,
      status: :scheduled,
      fires_at: Time.now + 2.hours
    )
    timed_node = FactoryGirl.create(:decision, parent: v1_timer, workflow: v1_workflow, status: :complete)
    v1_activity = FactoryGirl.create(:activity, parent: timed_node, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)

    v2_decision = v2_workflow.children.second

    expect(v2_workflow.children.count).to eq(2)
    expect(v2_decision.id).to eq(timed_node.id)
    expect(v2_decision.children.first.id).to eq(v1_activity.id)
  end

  it "converts v1 status to v2 server and client status" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)
    v2_decision = v2_workflow.children.first

    expect(v2_decision.current_server_status).to eq("complete")
    expect(v2_decision.current_client_status).to eq("complete")
  end

  it "converts a v1 timer" do
    Timecop.freeze
    v1_timer = FactoryGirl.create(
      :timer,
      parent: v1_signal,
      workflow: v1_workflow,
      status: :scheduled,
      fires_at: Time.now + 2.hours
    )

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

    v2_decision = v2_workflow.children.first
    v2_timer = v2_workflow.children.first

    expect(v2_timer.legacy_type).to eq("timer")
    expect(v2_timer.name).to eq("#{v1_timer.name}__timer__")
    expect(v2_timer.fires_at.to_s).to eq((Time.now + 2.hours).to_s)
    expect(v2_timer.current_server_status).to eq("started")
    expect(v2_timer.current_client_status).to eq("ready")
    expect(v2_timer.client_metadata).to eq({"version"=>"v2"})
    expect(v2_timer.client_data).to eq({"arguments" => [v1_timer.name.to_s], "options" => {}})
    expect(V2::Workers::AsyncWorker.jobs.count).to eq(1)
    expect(V2::Workers::AsyncWorker.jobs.first["at"].ceil).to eq((Time.now + 2.hours).to_f.ceil)
  end

  it "converts a completed v1 timer" do
    Timecop.freeze
    v1_timer = FactoryGirl.create(
      :timer,
      parent: v1_signal,
      workflow: v1_workflow,
      status: :complete,
      fires_at: Time.now + 2.hours
    )

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

    v2_decision = v2_workflow.children.first
    v2_timer = v2_workflow.children.first

    expect(v2_timer.legacy_type).to eq("timer")
    expect(v2_timer.name).to eq("#{v1_timer.name}__timer__")
    expect(v2_timer.fires_at.to_s).to eq((Time.now + 2.hours).to_s)
    expect(v2_timer.current_server_status).to eq("complete")
    expect(v2_timer.current_client_status).to eq("complete")
    expect(v2_timer.client_metadata).to eq({"version"=>"v2"})
    expect(v2_timer.client_data).to eq({"arguments" => [v1_timer.name.to_s], "options" => {}})
    expect(V2::Workers::AsyncWorker.jobs.count).to eq(0)
  end

  it "converts a v1 flag" do
    v1_flag = FactoryGirl.create(:flag, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_flag = v2_workflow.children.first

    expect(v2_flag.legacy_type).to eq("flag")
  end

  it "converts a v1 complete workflow" do
    v1_complete_workflow = FactoryGirl.create(:workflow_complete, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_complete_workflow = v2_workflow.reload.children.first

    expect(v2_complete_workflow.legacy_type).to eq("flag")
    expect(v2_workflow.reload.complete).to eq(true)
  end

  it "converts a v1 continue as new workflow" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete, inactive: true)
    v1_flag = FactoryGirl.create(:continue_as_new_workflow_flag, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)
    v2_decision = v2_workflow.reload.children.first
    v2_flag = v2_workflow.reload.children.second

    expect(v2_flag.legacy_type).to eq("flag")
    expect(v2_decision.current_server_status).to eq("deactivated")
  end

  it "converts a v1 branch" do
    v1_branch = FactoryGirl.create(:branch, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_branch = v2_workflow.children.first

    expect(v2_branch.legacy_type).to eq("branch")
  end

  it "converts a nested workflow" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
    v1_sub_workflow = FactoryGirl.create(:workflow, name: "Sub Workflow", user: v1_user, status: :executing, subject: { "name" => "Another subject" })
    v1_sub_workflow.parent = v1_decision
    v1_sub_workflow.save
    v1_sub_signal = FactoryGirl.create(:signal, parent: nil, workflow: v1_sub_workflow, status: :complete)
    v1_sub_decision = FactoryGirl.create(:decision, parent: v1_sub_signal, workflow: v1_sub_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)

    v2_sub_workflow = V2::Workflow.order(:created_at).last
    expect(v2_sub_workflow.subject).to eq(v1_sub_workflow.subject)
    expect(v2_sub_workflow.name).to eq(v1_sub_workflow.name.to_s)
    expect(v2_sub_workflow.decider).to eq(v1_sub_workflow.decider)
    expect(v2_sub_workflow.user_id).to eq(v1_sub_workflow.user_id)
    expect(v2_sub_workflow.complete).to eq(false)
    expect(v2_sub_workflow.children.count).to eq(1)

    v2_sub_decision = v2_sub_workflow.children.first
    expect(v2_sub_decision.id).to eq(v1_sub_decision.id)

    flag = v2_workflow.children.first.children.first
    expect(flag.name).to eq("Created sub-workflow #{v2_sub_workflow.id}")
  end

  context "can_migrate?" do
    it "does not migrate workflows with nodes that are not complete" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :sent_to_client, status: :open)

      expect { Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true) }.to raise_error Migration::MigrateWorkflow::WorkflowNotMigratable

      expect(v2_workflow.children.count).to eq(0)
      expect(v1_workflow.reload.migrated?).to eq(false)
    end

    it "migrates any complete timer" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      v1_timer = FactoryGirl.create(
        :timer,
        parent: v1_decision,
        workflow: v1_workflow,
        fires_at: Time.now - 80.minutes,
        status: :complete
      )

      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

      expect(V2::Workflow.count).to eq(1)
    end

    it "does not migrate workflows with timer nodes set to fire in one hour or less" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      v1_timer = FactoryGirl.create(
        :timer,
        parent: v1_decision,
        workflow: v1_workflow,
        fires_at: Time.now + 50.minutes,
        status: :scheduled
      )

      expect { Migration::MigrateWorkflow.call(v1_workflow, v2_workflow) }.to raise_error Migration::MigrateWorkflow::WorkflowNotMigratable

      expect(v2_workflow.children.count).to eq(0)
    end

    it "migrates resolved nodes" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      v1_timer = FactoryGirl.create(
        :activity,
        parent: v1_decision,
        workflow: v1_workflow,
        status: :resolved
      )

      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, migrate_all: true)

      expect(v2_workflow.nodes.count).to eq(2)
    end
  end

  context "workflows that require a full decision history" do
    it "migrates all decisions" do
      decision_1 = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      activity = FactoryGirl.create(:activity, parent: decision_1, workflow: v1_workflow, status: :complete)
      decision_2 = FactoryGirl.create(:decision, parent: activity, workflow: v1_workflow, status: :complete)

      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow, decision_history: true)

      expect(v2_workflow.children.count).to eq(3)
      expect(v2_workflow.children.first.name).to eq(decision_1.name.to_s)
      expect(v2_workflow.children.second.name).to eq(decision_2.name.to_s)
      expect(v2_workflow.children.last.id).to eq(decision_1.id)
    end
  end

  context "workflows with running timers" do
    before do
      v1_signal_2 = FactoryGirl.create(:signal, parent: nil, workflow: v1_workflow, status: :complete)
      decision_1 = FactoryGirl.create(:decision, parent: v1_signal_2, workflow: v1_workflow, status: :complete)
      @decision_2 = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      FactoryGirl.create(:activity, parent: decision_1, workflow: v1_workflow, status: :complete)
    end

    it "migrates only the top signal when signals do not have timers" do
      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

      expect(v1_workflow.reload.migrated?).to eq(true)
      expect(v2_workflow.reload.nodes.count).to eq(2)
      expect(v2_workflow.reload.children.count).to eq(2)
    end

    it "only migrates signals with timers or top node" do
      Timecop.freeze
      FactoryGirl.create(:timer, parent: @decision_2, fires_at: Time.now + 2.hours, status: :scheduled)

      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

      expect(v1_workflow.reload.migrated?).to eq(true)
      expect(v2_workflow.reload.nodes.count).to eq(3)
      expect(v2_workflow.reload.children.count).to eq(2)
    end

    it "will migrate only top signal nodes if no timers" do
      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

      expect(v1_workflow.reload.migrated?).to eq(true)
      expect(v2_workflow.reload.nodes.count).to eq(2)
      expect(v2_workflow.reload.children.count).to eq(2)
    end
  end

  context "workflows with sub-workflows" do
    it "migrates the full signal tree" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      v1_sub_workflow = FactoryGirl.create(:workflow, name: "Sub Workflow", user: v1_user, status: :executing, subject: { "name" => "Another subject" })
      v1_sub_workflow.parent = v1_decision
      v1_sub_workflow.save
      v1_sub_signal = FactoryGirl.create(:signal, parent: nil, workflow: v1_sub_workflow, status: :complete)
      v1_sub_decision = FactoryGirl.create(:decision, parent: v1_sub_signal, workflow: v1_sub_workflow, status: :complete)

      Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

      expect(v1_workflow.reload.migrated).to eq(true)
      expect(v1_sub_workflow.reload.migrated).to eq(true)
      expect(V2::Workflow.count).to eq(2)
      expect(v2_workflow.children.first.children.count).to eq(1)
    end
  end

  context "workflows with sub-workflows" do
    it "rolls back nested v1_workflow attribute changes when another nested workflow fails" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)

      v1_sub_workflow = FactoryGirl.create(:workflow, name: "Sub Workflow", workflow: v1_workflow, user: v1_user, status: :executing, subject: { "name" => "Another subject" })
      v1_sub_workflow.parent = v1_decision
      v1_sub_workflow.save
      v1_sub_signal = FactoryGirl.create(:signal, parent: nil, workflow: v1_sub_workflow, status: :complete)
      v1_sub_decision = FactoryGirl.create(:decision, parent: v1_sub_signal, workflow: v1_sub_workflow, status: :complete)

      v1_signal_2 = FactoryGirl.create(:signal, parent: nil, workflow: v1_workflow, status: :complete)
      v1_decision_2 = FactoryGirl.create(:decision, parent: v1_signal_2, workflow: v1_workflow, status: :complete)
      v1_sub_workflow_2 = FactoryGirl.create(:workflow, name: "Sub Workflow_2", workflow: v1_workflow, user: v1_user, status: :executing, subject: { "name" => "Another subject" })
      v1_sub_workflow_2.parent = v1_decision_2
      v1_sub_workflow_2.save
      v1_sub_signal_2 = FactoryGirl.create(:signal, parent: nil, workflow: v1_sub_workflow_2, status: :complete)
      v1_sub_decision_2 = FactoryGirl.create(:decision, parent: v1_sub_signal_2, workflow: v1_sub_workflow_2, status: :complete)
      v1_sub_decision_timer = FactoryGirl.create(:timer, parent: v1_sub_signal_2, workflow: v1_sub_workflow_2, status: :complete, status: :scheduled, fires_at: Time.now + 30.minutes)

      expect{Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)}.to raise_error Migration::MigrateWorkflow::WorkflowNotMigratable

      expect(V2::Workflow.count).to eq(1)
      expect(V2::Workflow.last).to eq(v2_workflow)
      expect(v1_workflow.reload.migrated).to eq(false)
      expect(v1_sub_workflow.reload.migrated).to eq(false)
      expect(v1_sub_workflow_2.reload.migrated).to eq(false)
      expect(v2_workflow.reload.migrated).to eq(false)
    end
  end

  context "has_special_cases?" do
    before do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)
      v1_activity = FactoryGirl.create(:activity, parent: v1_decision, workflow: v1_workflow, status: :complete)
      v1_activity_2 = FactoryGirl.create(:activity, parent: v1_decision, workflow: v1_workflow, status: :complete)
      FactoryGirl.create(:decision, parent: v1_activity_2, workflow: v1_workflow)
      @nested_decision = FactoryGirl.create(:decision, parent: v1_activity, workflow: v1_workflow, status: :complete)
    end

    it "returns true if the tree has a timer" do
      FactoryGirl.create(:timer, parent: @nested_decision)
      expect(Migration::MigrateWorkflow.has_special_cases?(v1_signal)).to eq(true)
    end

    it "returns false if the tree has a timer thats not complete" do
      FactoryGirl.create(:timer, parent: @nested_decision, status: :complete)
      expect(Migration::MigrateWorkflow.has_special_cases?(v1_signal)).to eq(false)
    end

    it "returns false if the tree has no timer or workflow" do
      expect(Migration::MigrateWorkflow.has_special_cases?(v1_signal)).to eq(false)
    end

    it "returns true if the tree has a workflow" do
      FactoryGirl.create(:workflow, parent: @nested_decision)
      expect(Migration::MigrateWorkflow.has_special_cases?(v1_signal)).to eq(true)
    end
  end
end
