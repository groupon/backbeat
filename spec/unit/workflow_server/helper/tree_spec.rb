require 'spec_helper'

describe Tree do

  context '#tree' do
    it 'calls #get_child_trees' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.should_receive(:get_child_trees).once

      activity.tree
    end

    it 'includes its childrens trees under the key :children in its tree if they exist' do
      activity = FactoryGirl.create(:activity, status: :open)
      activity_node = {id: activity.id, type: activity.event_type, name: activity.name, status: activity.status}
      activity.stub(:node).and_return(activity_node)

      activity.workflow.tree[:children].should eq [activity_node]
    end

    it 'does NOT include the key :children if it has no children' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.tree[:children].should be_nil
    end

    it 'defaults :big_tree to false' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.should_receive(:node).with(false, 1)

      activity.tree
    end
  end

  context '#big_tree' do
    it 'calls #tree with true' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.should_receive(:tree).with(true, 0)

      activity.big_tree
    end
  end

  context '#node' do
    it 'returns the identifying information for the object when :big_tree is not passed' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.send(:node).should eq ({id: activity.id, type: 'activity', name: activity.name, status: activity.status})
    end

    it 'returns the identifying information for the object when :big_tree is false' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.send(:node, false).should eq ({id: activity.id, type: 'activity', name: activity.name, status: activity.status})
    end

    it 'returns a hash of the object attributes when :big_tree is true' do
      activity = FactoryGirl.create(:activity, status: :open)

      result = activity.send(:node, true)

      result.should eq Tree::Node.new(activity.serializable_hash,0)
    end
  end

  context '#get_child_trees' do
    it 'calls tree on all the children and returns an array containing the result' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.workflow.send(:get_child_trees).should eq [activity.send(:node)]
    end

    it 'returns an empty array if there are no children' do
      activity = FactoryGirl.create(:activity, status: :open)

      activity.send(:get_child_trees).should eq []
    end
  end

end
