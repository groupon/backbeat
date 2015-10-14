require File.expand_path('../../config/environment',  __FILE__)

module ScheduledJobs
  class Base
    include Backbeat::Logging

    def perform
      raise NotImplementedError
    end

    def run
      puts "Running #{self.class.name} at #{Time.now}"
      perform
    end
  end
end
