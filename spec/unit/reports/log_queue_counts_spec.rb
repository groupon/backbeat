require 'spec_helper'
require 'webmock/rspec'
require_relative '../../../reports/log_counts.rb'

describe Reports::LogCounts do
  context "perform" do
    it "calls count methods" do
      expect(subject).to receive(:log_queue_counts)
      subject.perform
    end
  end

  context "log_count" do
    def expected_info(type, count_subject, count)
      expect(subject).to receive(:info).with(
        source: "Reports::LogCounts",
        type: type,
        subject: count_subject,
        count: count
      )
    end

    it "calls info with the correct info" do
      allow_any_instance_of(Sidekiq::RetrySet).to receive(:size).and_return(1)
      allow_any_instance_of(Sidekiq::ScheduledSet).to receive(:size).and_return(3)

      sidekiq_queues = {"queue_1"=>10, "queue_2"=>0}
      allow_any_instance_of(Sidekiq::Stats).to receive(:queues).and_return(sidekiq_queues)

      expected_info(:queue, "retry", 1)
      expected_info(:queue, "schedule" ,3)
      expected_info(:queue, "queue_1", 10)
      expected_info(:queue, "queue_2", 0)

      subject.send(:log_queue_counts)
    end
  end
end
