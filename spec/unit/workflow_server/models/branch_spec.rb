require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Branch do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:event) { FactoryGirl.create(:branch, workflow: workflow, client_data: {data: 123}, client_metadata: {git_sha: '12de3sdg'}) }

  context '#add_decision' do
    it 'raises an exception if a decision already exists' do
      event.add_decision(:test)
      event.children.count.should == 1
      expect{ event.add_decision(:test2) }.to raise_error('You cannot add a decision to a Branch that already has one!')
    end

    it 'allows a error event if a decision already exists' do
      event.add_decision(:test)
      event.children.count.should == 1
      event.add_decision("#{event.name}_error".to_sym)
      event.reload.children.count.should == 2
    end
  end
end
