require_relative 'mock_session'

def deploy(*args)
  application_root = YAML.load(args.first)["application"]["root"]
  require 'torquebox-configure'
  if Thread.current[:torquebox_config].nil?
    Thread.current[:torquebox_config] = TorqueBox::Configuration::GlobalConfiguration.new
    Thread.current[:torquebox_config_entry_map] = TorqueBox::Configuration::GlobalConfiguration::ENTRY_MAP
  end
  require "#{application_root}/config/torquebox"
end

module FakeTorquebox
  def self.run_jobs
    record_jobs
    yield if block_given?
    run_recorded_jobs
  ensure
    cleanup
  end

  def self.record_jobs
    @async_jobs = []
    MockSession.any_instance.stub(:publish) { |queue, message, options| @async_jobs << [queue, message, options] }
  end

  def self.run_recorded_jobs
    @async_jobs.each do |queue, message, options|
      FakeTorquebox.queue_processors(queue).each do |processor_def|
        processor_klass, options = *processor_def
        processor = processor_klass.constantize.new
        processor.on_message(message)
      end
    end
  end

  def self.cleanup
    @async_jobs = []
    MockSession.any_instance.unstub(:publish)
  end

  def self.queue_processors(queue)
    Thread.current[:torquebox_config][TorqueBox::CONFIGURATION_ROOT]["queue"][queue.name]["processor"]
  end

  def self.topic_processors
    Thread.current[:torquebox_config][TorqueBox::CONFIGURATION_ROOT]["topic"][queue.name]["processor"]
  end
end

module RSpec
  module Core
    module DSL
      def remote_describe(*args)
        yield
      end
    end
  end
end