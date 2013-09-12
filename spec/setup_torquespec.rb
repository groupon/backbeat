require 'torquespec'

module FakeTorquebox
  def self.run_jobs
    delete_all_jobs
    unstub
    yield if block_given?
    wait_for_jobs
  ensure
    stub
  end

  def self.delete_all_jobs
    TorqueBox::Messaging::Queue.list.map {|t| t.remove_messages }
  end

  def self.wait_for_jobs
    start = 0
    loop do
      break if TorqueBox::Messaging::Queue.list.map(&:count_messages).uniq == [0] || start >= 60
      ap "Waiting for jobs to complete since #{start}s"
      sleep 1
      start += 1
    end
  end

  def self.stub
    TorqueBox::Messaging::Queue.any_instance.stub(:publish)
    TorqueBox::Messaging::Topic.any_instance.stub(:publish)
  end

  def self.unstub
    TorqueBox::Messaging::Queue.any_instance.unstub(:publish)
    TorqueBox::Messaging::Topic.any_instance.unstub(:publish)
  end
end

RSpec.configuration.before(:each) do
  FakeTorquebox.stub
end