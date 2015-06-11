module Backbeat
  module Web
    module CurrentUserHelper
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end
    end
  end
end
