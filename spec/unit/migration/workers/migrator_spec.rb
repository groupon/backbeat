require "spec_helper"
require "migration/workers/migrator"

describe Migration::Workers::Migrator, v2: true do
  it "creates a v2 workflow given a v1 workflow id" do
    v1_user = FactoryGirl.create(:v1_user)
    v2_user = FactoryGirl.create(:v2_user, id: v1_user.id)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)
    v1_signal = FactoryGirl.create(:signal, workflow: v1_workflow, status: :complete)
    v1_decision = FactoryGirl.create(:decision, workflow: v1_workflow, parent: v1_signal, status: :complete)

    Migration::Workers::Migrator.new.perform(v1_workflow.id)

    expect(V2::Workflow.count).to eq(1)
    expect(V2::Workflow.first.id).to eq(v1_workflow.id)

    expect(V2::Node.count).to eq(1)
    expect(V2::Node.first.id).to eq(v1_decision.id)
  end


  it "logs" do
    v1_user = FactoryGirl.create(:v1_user)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)
    expect(Instrument).to receive(:instrument).with("Migration::Workers::Migrator_perform", { v1_workflow_id: v1_workflow.id })
    Migration::Workers::Migrator.new.perform(v1_workflow.id)
  end

  it "passes on the options" do
    v1_user = FactoryGirl.create(:v1_user)
    v2_user = FactoryGirl.create(:v2_user, id: v1_user.id)
    v1_workflow = FactoryGirl.create(:workflow, user: v1_user)

    expect(Migration::MigrateWorkflow).to receive(:call) do |v1_wf, v2_wf, options|
      expect(options[:decision_history]).to eq(true)
    end

    Migration::Workers::Migrator.new.perform(v1_workflow.id, { "decision_history" => true })
  end
end
