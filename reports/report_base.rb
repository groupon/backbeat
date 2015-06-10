require File.expand_path('../../config/environment',  __FILE__)
require 'mail'

module Reports
  class ReportBase

    def perform
      raise NotImplementedError
    end

    # run is so that it can be invoked as a job by TorqueBox
    def run
      puts "Running #{self.class.name} at #{Time.now}"
      perform
    end

  end
end
