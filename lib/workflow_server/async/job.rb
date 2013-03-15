require 'workflow_server/logger'

module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method_to_call, :args, :max_attempts)
    class Job < JobStruct
      include WorkflowServer::Logger

      def perform
        info(id: event.id, name: event.name, message: "#{method_to_call}_started")
        event.__send__(method_to_call, *args)
        info(id: event.id, name: event.name, message: "#{method_to_call}_succeeded")
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
        unless method_to_call.to_s == 'notify_client'
          event.update_status!(:error, :async_job_error)
        end
      end

      def event
        @event ||= WorkflowServer::Models::Event.find(event_id)
      end

      def self.jobs(event)
        Delayed::Job.where(handler: /WorkflowServer::Async::Job/).and(handler: /#{event.id}/)
      end

    end
  end
end