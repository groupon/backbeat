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
  def self.queue_processors(queue)
    Thread.current[:torquebox_config][TorqueBox::CONFIGURATION_ROOT]["queue"][queue.name]["processor"]
  end

  def self.topic_processors
    Thread.current[:torquebox_config][TorqueBox::CONFIGURATION_ROOT]["topic"][queue.name]["processor"]
  end
end