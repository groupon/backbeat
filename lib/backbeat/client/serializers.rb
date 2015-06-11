module Backbeat
  module Client
    class NodeSerializer
      def self.call(node)
        {
          id: node.id,
          mode: node.mode,
          name: node.name,
          workflow_id: node.workflow_id,
          parent_id: node.parent_id,
          user_id: node.user_id,
          client_data: node.client_data,
          metadata: node.client_metadata,
          subject: node.subject,
          decider: node.decider,
          current_server_status: node.current_server_status,
          current_client_status: node.current_client_status
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
