require 'workflow_server/logger'

module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method_to_call, :args, :max_attempts)
    class Job < JobStruct

      def perform
        logger.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_started")
        event.__send__(method_to_call, *args)
        logger.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_succeeded")
      rescue Exception => error
        logger.error(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_errored", error: error, backtrace: error.backtrace)
        raise
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

      def logger
        @logger ||= WorkflowServer::Logger.logger
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

module Delayed
  module Backend
    module Mongoid
      class Job
        # We do not want to rely on the moped driver to assign us a default id. We have seen in the past
        # that multiple processes may try to assign the same default id
        field :_id, type: String, default: ->{ UUIDTools::UUID.random_create.to_s }
      end
    end
  end
end