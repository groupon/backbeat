require 'workflow_server/logger'

module WorkflowServer
  module Async
    JobStruct ||= Struct.new(:event_id, :method_to_call, :args, :max_attempts)
    class Job < JobStruct
      extend WorkflowServer::Logger

      def self.queue
        :accounting_backbeat_server
      end

      def self.perform(job_data)
        job = new(*(job_data["data"]))
        begin
          job.perform
        rescue Exception => error
          # if the attempt to use Resque to perform this job fails, we will mimic delayed job
          # behavior and enqueue a reattempt in 5 seconds. DJ implements backoff semantics on future
          # retries. We end up doing 1 extra attempt in this flow, but we don't care
          event = WorkflowServer::Models::Event.find(job.event_id)
          schedule({event: event, method: job.method_to_call, args: job.args, max_attempts: job.max_attempts}, Time.now+5)
        end
      end

      def self.enqueue(job_data)
        #Resque.enqueue(self, data: [job_data[:event].id, job_data[:method], job_data[:args], job_data[:max_attempts]])
        @queue ||= TorqueBox::Messaging::Queue.new("/queues/accounting_backbeat_internal")
        @queue.publish(data: [job_data[:event].id, job_data[:method], job_data[:args], job_data[:max_attempts]])
      end

      def perform
        t0 = Time.now
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_started")
        event.__send__(method_to_call, *args)
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_succeeded", duration: Time.now - t0)
      rescue Exception => error
        self.class.error(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_errored", error: error, backtrace: error.backtrace, duration: Time.now - t0)
        Squash::Ruby.notify error
        raise
      end

      def self.schedule(options = {}, run_at = Time.now)
        job = new(options[:event].id, options[:method], options[:args], options[:max_attempts])
        job = Delayed::Job.enqueue(job, run_at: run_at)
        # Maintain a list of outstanding delayed jobs on the event
        options[:event].push(:_delayed_jobs, job.id)
        job
      end

      def before(job, *args)
        self.class.info(source: self.class.to_s, job: job.id, id: event.id, name: event.name, message: "#{method_to_call}_start_before_hook")
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
          event.update_status!(:error, :async_job_error)
        end
      rescue Exception => error
        self.class.error(source: self.class.to_s, message: 'encountered error in AsyncJob failure hook', error: error, backtrace: error.backtrace)
      end

      def event
        @event ||= WorkflowServer::Models::Event.find(event_id)
      end

      def self.jobs(event)
        Delayed::Job.where(:id.in => event._delayed_jobs)
      end

    end
  end
end

module Moped
  module BSON
    class ObjectId
      class Generator
        def generate(time, counter = 0)
          process_thread_id = (RUBY_ENGINE == 'jruby' ? "#{Process.pid}#{Thread.current.object_id}".hash % 0xFFFF : Process.pid)
          [time, @machine_id, process_thread_id, counter << 8].pack("N NX lXX NX")
        end
      end
    end
  end
end
