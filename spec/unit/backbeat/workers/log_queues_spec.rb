require 'spec_helper'

describe Backbeat::Workers::LogQueues do
  context "log_count" do
    def expect_info(type, count_subject, count)
      expect(Backbeat::Logger).to receive(:add) do |_, log|
        expect(log[:source]).to eq("Backbeat::Workers::LogQueues")
        expect(log[:data][:type]).to eq(type)
        expect(log[:data][:subject]).to eq(count_subject)
        expect(log[:data][:count]).to eq(count)
      end
    end

    it "logs info with the correct info" do
      allow_any_instance_of(Sidekiq::RetrySet).to receive(:size).and_return(1)
      allow_any_instance_of(Sidekiq::ScheduledSet).to receive(:size).and_return(3)

      sidekiq_queues = {"queue_1"=>10, "queue_2"=>0}
      allow_any_instance_of(Sidekiq::Stats).to receive(:queues).and_return(sidekiq_queues)

      expect_info(:queue, "retry", 1)
      expect_info(:queue, "schedule" ,3)
      expect_info(:queue, "queue_1", 10)
      expect_info(:queue, "queue_2", 0)

      subject.perform
    end
  end
end
