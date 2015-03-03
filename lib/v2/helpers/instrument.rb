module Instrument
  include WorkflowServer::Logger

  def self.instrument(event, *args)
    t0 = Time.now
    log_msg("#{event}_started", args)
    result = yield
    log_msg("#{event}_succeeded", args, duration: Time.now - t0)
    return result
  rescue Exception => error
    log_msg(
      "#{event}_errored",
      args,
      error_class: error.class.name,
      error: error.to_s,
      backtrace: error.backtrace,
      duration: Time.now - t0
    )
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
