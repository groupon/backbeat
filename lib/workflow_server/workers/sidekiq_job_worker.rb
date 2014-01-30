require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/logger'
require 'workflow_server/errors'
require 'workflow_server/config'

module WorkflowServer
  module Workers
    class SidekiqJobWorker
      include Sidekiq::Worker
      extend WorkflowServer::Logger

      sidekiq_options retry: 12,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:async_queue]

      sidekiq_retries_exhausted do |msg|
        begin
          event_id = msg['args'].first
          WorkflowServer::Models::Event.find(event_id).errored(msg['error_message'])
          self.error "#{msg['class']} failed with #{msg['args']}: #{msg['error_message']}."
        rescue Exception => e
          self.error "#{msg['class']} failed with #{msg['args']}: #{msg['error_message']} and could not mark the Event(#{event_id}) as errored because of #{e.class}:#{e.message}."
        end
      end

      def perform(event_id, method_to_call, args, max_attempts)
        t0 = Time.now
        event = WorkflowServer::Models::Event.find(event_id)
        raise WorkflowServer::EventNotFound.new("Event with id(#{event_id}) not found") if event.nil?
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_started")
        event.__send__(method_to_call, *args)
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_succeeded", duration: Time.now - t0)
      rescue WorkflowServer::EventNotFound, Backbeat::TransientError => error
        self.class.info(source: self.class.to_s, id: event_id, name: event.try(:name) || "unknown", message: "#{method_to_call}:#{error.message.to_s}", error: error.to_s, backtrace: error.backtrace, duration: Time.now - t0)
        raise
      rescue Exception => error
        self.class.error(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_errored", error: error.to_s, backtrace: error.backtrace, duration: Time.now - t0)
        Squash::Ruby.notify error
        raise
      end

    end
  end
end
