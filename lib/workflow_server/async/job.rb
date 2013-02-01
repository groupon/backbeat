module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method_to_call, :args, :max_attempts)
    class Job < JobStruct
      def perform
        event.__send__(method_to_call, *args)
      end

      def self.schedule(options = {}, run_at = Time.now)
        job = new(options[:event].id, options[:method], options[:args], options[:max_attempts])
        Delayed::Job.enqueue(job, run_at: run_at)
      end

      # add a failure hook when everything fails
      def failure
        # TODO - notify_client errors can be ignored (this looks like
        # a bad hack, and i might change this to work based off
        # priority. anyways, should work for now)
        unless method == :notify_client
          event.update_status!(error, :async_job_error)
        end
      end

      def event
        @event ||= WorkflowServer::Models::Event.find(event_id)
      end
    end
  end
end