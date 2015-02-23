require "spec_helper"
require "migration/migrate_workflow"

describe Migration::MigrateWorkflow, v2: true do
  let(:v1_user) { FactoryGirl.create(:v1_user) }
  let(:v1_workflow) { FactoryGirl.create(:workflow, user: v1_user) }
  let(:v1_signal) { FactoryGirl.create(:signal, parent: nil, workflow: v1_workflow) }

  let(:v2_user) { FactoryGirl.create(:v2_user, uuid: v1_user.id) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow, user: v2_user) }

  context ".queue_conversion_batch" do
    it "queues a batch of workflow ids to the conversion worker" do
      FactoryGirl.create(:workflow, user: v1_user)
      10.times do |i|
        FactoryGirl.create(
          :workflow,
          name: "Workflow #{i}",
          workflow_type: :international,
          user: v1_user
        )
      end

      Migration::MigrateWorkflow.queue_conversion_batch([:international])

      expect(Migration::Workers::Migrator.jobs.count).to eq(10)
    end
  end

  context ".find_or_create_v2_workflow" do
    it "returns v2 workflow if it already exists" do
      FactoryGirl.create(:v2_workflow, name: "wrong workflow", user: v2_user)
      v2_workflow = FactoryGirl.create(:v2_workflow, uuid: v1_workflow.id, user: v2_user)
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
      expect(workflow.uuid).to eq(v1_workflow.id.gsub("-", ""))
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
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_decision = v2_workflow.children.first

    expect(v2_decision.uuid).to eq(v1_decision.id.gsub("-", ""))
    expect(v2_decision.mode).to eq("blocking")
    expect(v2_decision.name).to eq(v1_decision.name.to_s)
    expect(v2_decision.parent).to eq(v2_workflow)
    expect(v2_decision.user_id).to eq(v2_user.id)
    expect(v2_decision.legacy_type).to eq("decision")
  end

  it "marks the v1 workflow as migrated" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)

    expect(v1_workflow.reload.migrated?).to eq(true)
  end

  it "migrates great plains style workflow" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow)
    v1_activity = FactoryGirl.create(:activity, parent: v1_decision, workflow: v1_workflow)
    v1_sub_activity = FactoryGirl.create(:activity, parent: v1_activity, workflow: v1_workflow)
    v1_sub_decision = FactoryGirl.create(:decision, parent: v1_activity, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_decision = v2_workflow.children.first
    v2_activity = v2_decision.children.first

    expect(v2_decision.children.count).to eq(1)
    expect(v2_activity.children.count).to eq(2)

    sub_activity = v2_activity.children.first

    expect(sub_activity.name).to eq(v1_sub_activity.name.to_s)
    expect(sub_activity.uuid).to eq(v1_sub_activity.id.gsub("-", ""))
    expect(sub_activity.legacy_type).to eq("activity")

    sub_decision = v2_activity.children.second
    expect(sub_decision.name).to eq(v1_sub_decision.name.to_s)
    expect(sub_decision.uuid).to eq(v1_sub_decision.id.gsub("-", ""))
    expect(sub_decision.legacy_type).to eq("decision")
  end

  it "converts v1 status to v2 server and client status" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
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
    expect(V2::Workers::AsyncWorker.jobs.count).to eq(1)
    expect(V2::Workers::AsyncWorker.jobs.first["args"]).to eq(["V2::Events::StartNode", "V2::Node", v2_timer.id, 4])
    expect(V2::Workers::AsyncWorker.jobs.first["at"].ceil).to eq((Time.now + 2.hours).to_f.ceil)
  end

  it "converts a v1 flag" do
    v1_flag = FactoryGirl.create(:flag, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_flag = v2_workflow.children.first

    expect(v2_flag.legacy_type).to eq("flag")
  end

  it "converts a v1 complete workflow" do
    v1_complete_workflow = FactoryGirl.create(:workflow_complete, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_complete_workflow = v2_workflow.reload.children.first

    expect(v2_complete_workflow.legacy_type).to eq("flag")
    expect(v2_workflow.reload.complete).to eq(true)
  end

  it "converts a v1 continue as new workflow" do
    v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :complete, inactive: true)
    v1_flag = FactoryGirl.create(:continue_as_new_workflow_flag, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_decision = v2_workflow.reload.children.first
    v2_flag = v2_workflow.reload.children.second

    expect(v2_flag.legacy_type).to eq("flag")
    expect(v2_decision.current_server_status).to eq("deactivated")
  end

  it "converts a v1 branch" do
    v1_branch = FactoryGirl.create(:branch, parent: v1_signal, workflow: v1_workflow)

    Migration::MigrateWorkflow.call(v1_workflow, v2_workflow)
    v2_branch = v2_workflow.children.first

    expect(v2_branch.legacy_type).to eq("branch")
  end

  context "can_migrate?" do
    it "does not migrate workflows with nodes that are not open, ready, or complete" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow, status: :sent_to_client)

      expect { Migration::MigrateWorkflow.call(v1_workflow, v2_workflow) }.to raise_error Migration::MigrateWorkflow::WorkflowNotMigratable

      expect(v2_workflow.children.count).to eq(0)
      expect(v1_workflow.reload.migrated?).to eq(false)
    end

    it "migrates any complete timer" do
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow)
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
      v1_decision = FactoryGirl.create(:decision, parent: v1_signal, workflow: v1_workflow)
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
  end
end
