require 'app'

module WorkflowServer
  module Async

    class MessageProcessor < TorqueBox::Messaging::MessageProcessor

      def on_message(body)
        #queue = TorqueBox::Messaging::Queue.new('/queues/test')
        @job = Job.new(*body[:data])
        #queue.publish('milton')
        @job.perform
      end

      def on_error(error)
        queue = TorqueBox::Messaging::Queue.new('/queues/test')
        queue.publish(error)

        # if the attempt to use Resque to perform this job fails, we will mimic delayed job
        # behavior and enqueue a reattempt in 5 seconds. DJ implements backoff semantics on future
        # retries. We end up doing 1 extra attempt in this flow, but we don't care
        event = WorkflowServer::Models::Event.find(@job.event_id)
        Job.schedule({event: event, method: @job.method_to_call, args: @job.args, max_attempts: @job.max_attempts}, Time.now+5)
      end
    end

  end
end