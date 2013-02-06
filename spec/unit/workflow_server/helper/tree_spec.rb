require 'spec_helper'

describe Tree do

  before do
    @activity = FactoryGirl.create(:activity, status: :open)
    @activity_node = Tree::Node.new(@activity)
  end

  context '#tree' do
    it 'calls #get_child_trees' do
      @activity.should_receive(:get_child_trees).and_return([])

      @activity.tree
    end

    it 'includes its childrens trees under the key :children in its tree if they exist' do
      @activity.workflow.tree[:children].should eq [@activity_node]
    end

    it 'does NOT include the key :children if it has no children' do
      @activity.tree[:children].should be_nil
    end
  end

  context '#get_child_trees' do
    it 'calls tree on all the children and returns an array containing the result' do
      @activity.workflow.send(:get_child_trees).should eq [@activity_node]
    end

    it 'returns an empty array if there are no children' do
      @activity.send(:get_child_trees).should eq []
    end
  end

end
