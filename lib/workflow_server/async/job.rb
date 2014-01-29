require 'workflow_server/logger'
require 'workflow_server/errors'
require 'workflow_server/workers'

module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method_to_call, :args, :max_attempts)

    class Job < JobStruct
      extend WorkflowServer::Logger

      def self.enqueue(job_data, run_at = Time.now)
        delay = run_at - Time.now
        data = [job_data[:event].id, job_data[:method], job_data[:args], job_data[:max_attempts]]

        if delay <= 0.0
          WorkflowServer::Workers::SidekiqJobWorker.perform_async(*data)
        else
          WorkflowServer::Workers::SidekiqJobWorker.perform_in(delay, *data)
        end
      end

      def self.schedule(options = {}, run_at = Time.now)
        event_id = options[:event_id] || options[:event].id
        job = new(event_id, options[:method], options[:args], options[:max_attempts])
        job = Delayed::Job.enqueue(job, run_at: run_at)
        # Maintain a list of outstanding delayed jobs on the event
        options[:event].push(:_delayed_jobs, job.id) if options[:event]
        job
      end

      def perform
        WorkflowServer::Workers::SidekiqJobWorker.perform_async(event_id, method_to_call, args, max_attempts)
      end

      def success(job, *args)
        # Remove this job from the list of outstanding jobs
        event.pull(:_delayed_jobs, job.id)
      end

      # add a failure hook when everything fails
      def failure
        # TODO - notify_client errors can be ignored (this looks like
        # a bad hack, and i might change this to work based off
        # priority. anyways, should work for now)
        unless method_to_call.to_s == 'notify_client'
          self.class.error(source: self.class.to_s, event: event_id, failed: true, error: "ERROR")
          event.update_status!(:error, :async_job_error)
        end
      rescue Exception => error
        self.class.error(source: self.class.to_s, message: 'encountered error in AsyncJob failure hook', error: error, backtrace: error.backtrace)
      end

      def event
        @event ||= WorkflowServer::Models::Event.find(event_id)
        raise WorkflowServer::EventNotFound.new("Event with id(#{event_id}) not found") if @event.nil?
        @event
      end

      def self.jobs(event)
        Delayed::Job.where(:id.in => event._delayed_jobs)
      end

    end
  end
end

# TODO - Naren swears he'll add a comment here. 2013/09/12
module Moped
  module BSON
    class ObjectId
      class Generator
        def generate(time, counter = 0)
          process_thread_id = (RUBY_ENGINE == 'jruby' ? "#{Process.pid}#{Thread.current.object_id}".hash % 0xFFFF : Process.pid)
          [time, @machine_id, process_thread_id, counter << 8].pack('N NX lXX NX')
        end
      end
    end
  end
end
