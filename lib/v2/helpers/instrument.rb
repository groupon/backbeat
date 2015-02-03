module Instrument
  include WorkflowServer::Logger
  def self.instrument(node, event)
    t0 = Time.now
    log_msg(node, "#{event}_started")
    result = yield
    log_msg(node, "#{event}_succeeded", duration: Time.now - t0)
    return result
  rescue Exception => error
    log_msg(node, 
            "#{event}_errored",
            error_class: error.class,
            error: error.to_s,
            backtrace: error.backtrace,
            duration: Time.now - t0
           )
    raise error
  end

  def self.log_msg(node, message, options = {})
    info({
      source: self.class.to_s,
      id: node.id,
      name: node.name,
      message: message
    }.merge(options))
  end
end


