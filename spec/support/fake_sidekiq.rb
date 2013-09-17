# -*- encoding : utf-8 -*-
class FakeSidekiq
  attr_accessor :async_jobs

  def self.for
    fake_sidekiq = FakeSidekiq.new
    yield
    fake_sidekiq.run_async_jobs
    fake_sidekiq.cleanup
  end

  def initialize
    @async_jobs = []
    # we map to make sure all the keys that are symbols are converted to strings, since that's what happens in real Sidekiq 
    Sidekiq::Client.stub(:enqueue)    { |*args| @async_jobs.push(args.map {|m| m.is_a?(Hash) ? HashWithIndifferentAccess.new(m).to_hash : m } ) }
    Sidekiq::Client.stub(:enqueue_to) { |*args| @async_jobs.push(args[1..-1].map {|m| m.is_a?(Hash) ? HashWithIndifferentAccess.new(m).to_hash : m } ) }
  end

  # These are async jobs enqueued during the for block. We expect each job to be array with two members
  # The first member is the class name on which we should call perform.
  # The second member are the arguments that we will pass to the perform method.
  def run_async_jobs
    #original_jobs = @async_jobs.dup
    @async_jobs.each do |klass, *args|
      klass.send(:perform, *args)
    end
    #raise "running async jobs created unexpected jobs: #{@async_jobs - original_jobs}" unless @async_jobs == original_jobs
  end

  def cleanup
    Sidekiq::Client.unstub(:enqueue)
    Sidekiq::Client.unstub(:enqueue_to)
  rescue Exception => e
  end
end
