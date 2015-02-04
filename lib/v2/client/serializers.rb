module V2
  module Client
    class ActivitySerializer
      def self.call(node)
        {
          id: node.id,
          mode: node.mode,
          name: node.name,
          parent_id: node.parent_id,
          workflow_id: node.workflow_id,
          user_id: node.user_id,
          client_data: node.client_data
        }
      end
    end

    class DecisionSerializer
      def self.call(node)
        {
          id: node.id,
          name: node.name,
          parent_id: node.parent_id,
          user_id: node.user_id,
          client_data: node.client_data,
          subject: node.subject,
          decider: node.decider
        }
      end
    end

    class NotificationSerializer
      def self.call(node, message, error = nil)
        {
          notification: {
            type: node.class.to_s,
            id: node.id,
            name: node.name,
            subject: node.subject,
            message: message
          },
          error: ErrorSerializer.call(error)
        }
      end
    end

    class ErrorSerializer
      def self.call(error)
        case error
        when StandardError
          {
            error_klass: error.class.to_s,
            message: error.message
          }.tap { |data| data[:backtrace] = error.backtrace if error.backtrace }
        when String
          { error_klass: error.class.to_s, message: error }
        else
          error
        end
      end
    end
  end
end
