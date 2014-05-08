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
          event = WorkflowServer::Models::Event.find(event_id)
          event.transaction do
            event.errored(msg['error_message'])
          end
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
        event.transaction do
          event.__send__(method_to_call, *args)
        end
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_succeeded", duration: Time.now - t0)
      rescue WorkflowServer::EventNotFound, Backbeat::TransientError => error
        self.class.info(source: self.class.to_s, id: event_id, name: event.try(:name) || "unknown", message: "#{method_to_call}:#{error.message.to_s}", error_class: error.class, error: error.to_s, backtrace: error.backtrace, duration: Time.now - t0)
        raise error
      rescue Exception => error
        self.class.info(source: self.class.to_s, id: event.id, name: event.name, message: "#{method_to_call}_errored", error_class: error.class, error: error.to_s, backtrace: error.backtrace, duration: Time.now - t0)
        raise error
      end

    end
  end
end
