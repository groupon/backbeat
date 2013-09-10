module FakeTorquebox
  VERSION = "0.0.1"
  def self.for
    prepare_to_record_jobs unless run_jboss?
    yield if block_given?
    run_recorded_jobs unless run_jboss?
  end

  def self.run_jboss?
    !ENV["RUN_JBOSS"].nil?
  end

  def self.prepare_to_record_jobs
    @async_jobs = []
    TorqueBox::Messaging::Queue.any_instance.stub(:publish) { |*args| @async_jobs << args }
  end

  def self.run_recorded_jobs
    puts "running the recorded jobs #{@async_jobs}"
    @async_jobs.each do |job|
      puts "running #{job}"
      WorkflowServer::Async::MessageProcessor.new.on_message(*job)
    end
    # Figure out where to send this message
    @async_jobs = nil
    TorqueBox::Messaging::Queue.any_instance.unstub(:publish)
  end
end

if FakeTorquebox.run_jboss?
  require 'torquespec'

  TorqueSpec.configure do |config|
    config.jboss_home = "#{ENV['HOME']}/.immutant/current/jboss"
    config.jvm_args = "-Xms2048m -Xmx2048m -XX:MaxPermSize=512m -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -Djruby.home=#{config.jruby_home}"
  end

  module TorqueBox
    module Messaging
      class Queue < Destination
        # publish_and_receive ensures that jobs run synchronously
        alias_method :publish, :publish_and_receive
      end
    end
  end
else
  module TorqueBox
    module Messaging
      class Queue < Destination
        def publish(*args)
        end
      end
    end
  end
  def deploy(*args)
    # ignore anything that is deployed
  end
end