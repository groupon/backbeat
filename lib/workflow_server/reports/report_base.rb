require 'mail'

module WorkflowServer
  module Reports
    class ReportBase
      class << self

        def perform
          raise NotImplementedError
        end

      end
    end
  end
end
