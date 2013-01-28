module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method, :args, :max_attempts)
    class Job < JobStruct
      def perform
        event = WorkflowServer::Models::Event.find(event_id)
        event.__send__(method, *args)
      end

      def self.schedule(options = {}, run_at = Time.now)
        job = new(options[:event].id, options[:method], options[:args], options[:max_attempts])
        Delayed::Job.enqueue(job, run_at: run_at)
      end
    end
  end
end