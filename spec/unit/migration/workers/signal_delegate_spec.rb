require "spec_helper"

describe Migration::Workers::SignalDelegate, v2: true do

  let(:v1_user) { FactoryGirl.create(:v1_user) }
  let(:v1_workflow) { FactoryGirl.create(:workflow, user: v1_user) }
  let(:v2_user) { FactoryGirl.create(:v2_user, uuid: v1_user.id) }

  before do
    @v2_workflow = FactoryGirl.create(:v2_workflow, user: v2_user, migrated: false, uuid: v1_workflow.id)
  end

  def log_data(v1_workflow_id)
    {
      v1_workflow_id: v1_workflow_id,
      params: {'name' => 'test', 'options' => { 'client_data' => {'data' => '123'}}},
      client_data: {'data' => '123'},
      client_metadata: {'blah' => '456'}
    }
  end

  context "perform" do
    it "sends v1 signal" do
      WorkflowServer::Client.stub(:make_decision)
      params = {name: 'test', options: { client_data: {data: '123'}}}
      client_data = {data: '123'}
      client_metadata = {blah: '456'}

      allow(Instrument).to receive(:instrument).and_call_original
      allow(Instrument).to receive(:log_msg).and_call_original

      Migration::Workers::SignalDelegate.perform_async(v1_workflow.id, params, client_data, client_metadata)
      Migration::Workers::SignalDelegate.drain
      WorkflowServer::Workers::SidekiqJobWorker.drain

      v1_workflow.reload
      v1_workflow.signals.first.client_data.should == {'data' => '123'}
      v1_workflow.signals.first.client_metadata.should == {'blah' => '456'}
      decision = v1_workflow.signals.first.children.first
      decision.name.should == :test
      decision.status.should == :sent_to_client

      expect(Instrument).to have_received(:instrument).with("Migration::Workers::SignalDelegate_perform", log_data(v1_workflow.id))
      expect(Instrument).to have_received(:log_msg).with("Migration::Workers::SignalDelegate_v1_signal_sent", log_data(v1_workflow.id))
    end

    it "sends v2 signal" do
      @v2_workflow.update_attributes!(migrated: true)

      params = {name: 'test', options: { client_data: {data: '123'}}}
      client_data = {data: '123'}
      client_metadata = {blah: '456'}

      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, @v2_workflow)
      allow(Instrument).to receive(:instrument).and_call_original
      allow(Instrument).to receive(:log_msg).and_call_original

      Migration::Workers::SignalDelegate.perform_async(v1_workflow.id, params, client_data, client_metadata)
      Migration::Workers::SignalDelegate.drain

      new_node = @v2_workflow.nodes.last
      expect(new_node.legacy_type).to eq("decision")
      expect(new_node.current_server_status).to eq("ready")
      expect(new_node.current_client_status).to eq("ready")
      expect(new_node.client_data).to eq({ 'data' => '123' })
      expect(new_node.client_metadata).to eq({"blah"=>"456", "version"=>"v2"})

      expect(Instrument).to have_received(:instrument).with("Migration::Workers::SignalDelegate_perform", log_data(v1_workflow.id))
      expect(Instrument).to have_received(:log_msg).with("Migration::Workers::SignalDelegate_v2_signal_sent", log_data(v1_workflow.id))
    end
  end
end
