require 'spec_helper'

describe Backbeat::Web::Middleware::SidekiqStats, :api_test do

  context '/sidekiq_stats' do
    it 'catches the request, returns 200 and queue stats' do
      stats = double(Sidekiq::Stats, processed: 23, failed: 42, enqueued: 666, scheduled_size: 0, retry_size: 123, queues: {"queue1" => 0, "queue2" => 0} )
      history = double(Sidekiq::Stats::History, processed: {"2013-11-08" => 15}, failed: {"2013-11-08" => 19})

      q1 = double(Sidekiq::Queue, latency: 10)
      q2 = double(Sidekiq::Queue, latency: 20)
      expect(Sidekiq::Queue).to receive(:new).with("queue1").and_return(q1)
      expect(Sidekiq::Queue).to receive(:new).with("queue2").and_return(q2)
      allow(Sidekiq::Stats).to receive_messages(new: stats)

      expect(Sidekiq::Stats::History).to receive(:new).with(1).and_return(history)

      response = get '/sidekiq_stats'
      expect(response.status).to eq(200)

      JSON.parse(response.body) == {
        "latency" => { "queue1" => 10, "queue2" => 20 },
        "today"   => { "processed" => 15, "failed" => 19 },
        "processed" => 23,
        "failed"    => 42,
        "enqueued"  => 666,
        "scheduled_size" => 0,
        "retry_size" => 123
      }
    end
  end
end
