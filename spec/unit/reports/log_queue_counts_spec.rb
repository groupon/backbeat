require 'spec_helper'
require 'webmock/rspec'
require_relative '../../../reports/log_queue_counts.rb'

describe Reports::LogQueueCounts, v2: true do
  context "perform" do

    def expected_info(queue_name, size)
      expect(subject).to receive(:info).with(
        source: "Reports::LogQueueCounts",
        queue_name: queue_name,
        size: size
      )
    end
    it "calls info with the correct info" do
      allow_any_instance_of(Sidekiq::RetrySet).to receive(:size).and_return(1)
      allow_any_instance_of(Sidekiq::ScheduledSet).to receive(:size).and_return(3)

      sidekiq_queues = {"queue_1"=>10, "queue_2"=>0}
      allow_any_instance_of(Sidekiq::Stats).to receive(:queues).and_return(sidekiq_queues)

      expected_info("retry",1)
      expected_info("schedule",3)
      expected_info("queue_1",10)
      expected_info("queue_2",0)

      subject.perform
    end
  end
end
