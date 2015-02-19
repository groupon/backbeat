require "spec_helper"

describe Migration::Workers::SignalDelegate, v2: true do

  let(:v1_user) { FactoryGirl.create(:v1_user) }
  let(:v1_workflow) { FactoryGirl.create(:workflow, user: v1_user) }
  let(:v2_user) { FactoryGirl.create(:v2_user, uuid: v1_user.id) }

  before do
    @v2_workflow = FactoryGirl.create(:v2_workflow, user: v2_user, migrated: false, uuid: v1_workflow.id)
  end

  context "perform" do
    it "sends v1 signal" do
      WorkflowServer::Client.stub(:make_decision)
      params = {name: 'test', options: { client_data: {data: '123'}, client_metadata: {metadata: '456'}}}
      client_data = {data: '123'}
      client_metadata = {metadata: '456'}

      Migration::Workers::SignalDelegate.perform_async(v1_workflow.id, v1_user.id, params, client_data, client_metadata)
      Migration::Workers::SignalDelegate.drain

      WorkflowServer::Workers::SidekiqJobWorker.drain

      v1_workflow.reload
      v1_workflow.signals.first.client_data.should == {'data' => '123'}
      v1_workflow.signals.first.client_metadata.should == {'metadata' => '456'}
      decision = v1_workflow.signals.first.children.first
      decision.name.should == :test
      decision.status.should == :sent_to_client
    end

    it "sends v2 signal" do
      @v2_workflow.update_attributes!(migrated: true)

      params = {name: 'test', options: { client_data: {data: '123'}, client_metadata: {blah: '456'}}}
      client_data = {data: '123'}
      client_metadata = {metadata: '456'}

      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, @v2_workflow)

      Migration::Workers::SignalDelegate.perform_async(v1_workflow.id, v1_user.id, params, client_data, client_metadata)
      Migration::Workers::SignalDelegate.drain

      new_node = @v2_workflow.nodes.last
      expect(new_node.legacy_type).to eq("decision")
      expect(new_node.current_server_status).to eq("ready")
      expect(new_node.current_client_status).to eq("ready")
      expect(new_node.client_data).to eq({ 'data' => '123' })
      expect(new_node.client_metadata).to eq({"blah"=>"456", "version"=>"v2"})
    end
  end
end
