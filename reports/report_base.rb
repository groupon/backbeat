require File.expand_path('../../config/environment',  __FILE__)
require 'mail'

module Reports
  class ReportBase

    def perform
      raise NotImplementedError
    end

    def run
      puts "Running #{self.class.name} at #{Time.now}"
      perform
    end
  end
end
