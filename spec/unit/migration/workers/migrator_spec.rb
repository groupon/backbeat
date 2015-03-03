require "spec_helper"
require "migration/workers/migrator"

describe Migration::Workers::Migrator, v2: true do
  it "creates a v2 workflow given a v1 workflow id" do
    v1_user = FactoryGirl.create(:v1_user)
    v2_user = FactoryGirl.create(:v2_user, uuid: v1_user.id)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)
    v1_signal = FactoryGirl.create(:signal, workflow: v1_workflow)
    v1_decision = FactoryGirl.create(:decision, workflow: v1_workflow, parent: v1_signal)

    Migration::Workers::Migrator.new.perform(v1_workflow.id)

    expect(V2::Workflow.count).to eq(1)
    expect(V2::Workflow.first.uuid).to eq(v1_workflow.id.gsub("-", ""))

    expect(V2::Node.count).to eq(1)
    expect(V2::Node.first.uuid).to eq(v1_decision.id.gsub("-", ""))
  end

  it "returns if workflow is already migrated" do
    v1_user = FactoryGirl.create(:v1_user)
    v2_user = FactoryGirl.create(:v2_user, uuid: v1_user.id)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)

    expect(Migration::MigrateWorkflow).to receive(:call).and_call_original.once

    Migration::Workers::Migrator.new.perform(v1_workflow.id)
    Migration::Workers::Migrator.new.perform(v1_workflow.id)
  end

  it "logs" do
    v1_user = FactoryGirl.create(:v1_user)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)
    expect(Instrument).to receive(:instrument).with("Migration::Workers::Migrator_perform", { v1_workflow_id: v1_workflow.id })
    Migration::Workers::Migrator.new.perform(v1_workflow.id)
  end
end
