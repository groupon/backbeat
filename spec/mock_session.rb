class MockSession
  def publish(queue, message, options)
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