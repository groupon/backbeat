# -*- encoding : utf-8 -*-
module WorkflowServer
  class Events
    def self.event_callbacks
      return @event_callbacks || {}
    end

    def self.event_callbacks=(value)
      @event_callbacks = value
    end

    def self.attach_to_all_error_events(&callback)
      @event_callbacks ||= {}
      (@event_callbacks[:error_callbacks] ||= []) << callback
    end

    def self.attach_to_all_events(&callback)
      @event_callbacks ||= {}
      (@event_callbacks[:event_callbacks] ||= []) << callback
    end

    def self.notify_of(event, options)
      return unless @event_callbacks && @event_callbacks[:event_callbacks]
      @event_callbacks[:event_callbacks].each do |callback|
        callback.call(event, options)
      end
    end

    def self.notify_of_error(event, error, options)
      return unless @event_callbacks && @event_callbacks[:error_callbacks]
      @event_callbacks[:error_callbacks].each do |callback|
        callback.call(event, error, options)
      end
    end
  end
end
