class MockSession
  def publish(queue, message, options)
    FakeTorquebox.queue_processors(queue).each do |processor_def|
      processor_klass, options = *processor_def
      processor = processor_klass.constantize.new
      processor.on_message(message)
    end
  end
end

module TorqueBox
  module Messaging
    class Destination
      def wait_for_destination(*args)
        yield
      end
      def with_session(*args)
        yield MockSession.new
      end
    end
  end
end