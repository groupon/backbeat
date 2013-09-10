require_relative 'mock_queues'

def deploy(*args)
  application_root = YAML.load(args.first)["application"]["root"]
  require 'torquebox-configure'
  Thread.current[:torquebox_config] = TorqueBox::Configuration::GlobalConfiguration.new
  Thread.current[:torquebox_config_entry_map] = TorqueBox::Configuration::GlobalConfiguration::ENTRY_MAP
  require "#{application_root}/config/torquebox"
end

module FakeTorquebox
  def self.for
    prepare_to_record_jobs unless run_jboss?
    yield if block_given?
    run_recorded_jobs unless run_jboss?
  end

  def self.prepare_to_record_jobs
    MockQueues.record
  end

  def self.run_recorded_jobs
    MockQueues.run
  end

  def self.queue_processors(queue)
    Thread.current[:torquebox_config]["<root>"]["queue"][queue.name]["processor"]
  end

  def self.topic_processors
    Thread.current[:torquebox_config]["<root>"]["topic"][queue.name]["processor"]
  end
end