require_relative 'mock_session'

class MockQueues
  def self.record
    @async_jobs = []
    MockSession.any_instance.stub(:publish) { |queue, message, options| @async_jobs << [queue, message] }
  end
  def self.run
    @async_jobs.each do |queue, job|
      FakeTorquebox.queue_processors(queue).each do |processor_def|
        processor_klass, options = *processor_def
        processor = processor_klass.constantize.new
        processor.on_message(job)
      end
    end
    @async_jobs = []
  end
end

module TorqueBox
  module Messaging
    class Queue < Destination
      def wait_for_destination(*args)
        yield
      end
      def with_session(*args)
        yield MockSession.new
      end
    end
  end
end
