require 'mail'

module Reports
  class ReportBase

    def perform
      raise NotImplementedError
    end

  end
end
