module Backbeat
  module Events
    class Event
      def self.scheduler(type = nil)
        if type
          @scheduler = type
        else
          @scheduler
        end
      end

      def self.call(node)
        new.call(node)
      end

      def scheduler
        self.class.scheduler
      end

      def name
        self.class.name
      end
    end

    module ResponseHandler
      attr_reader :response

      def initialize(response = {})
        @response = response
      end
    end
  end
end
