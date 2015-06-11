module Backbeat
  module Instrument
    include Logging

    def self.instrument(event, *args)
      t0 = Time.now
      log_msg("#{event}_started", args)
      result = yield
      log_msg("#{event}_succeeded", args, duration: Time.now - t0)
      return result
    rescue Exception => error
      handle_exception(event, error, t0,  *args)
      raise error
    end

    def self.handle_exception(event, error, t0,  *args)
      log_msg(
        "#{event}_errored",
        args,
        error_class: error.class.name,
        error: error.to_s,
        backtrace: error.backtrace,
        duration: Time.now - t0
      )
    rescue Exception => error
      info(event_name: :error_logging_error, name: event.name)
      raise error
    end


    def self.log_msg(message, args, options = {})
      info({
        source: self.class.to_s,
        message: message,
        args: args
      }.merge(options))
    end
  end
end
