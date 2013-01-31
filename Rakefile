#!/usr/bin/env rake

require_relative 'app'
require 'rake'

task :create_indexes do |task|
  mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, "config", "mongoid.yml"))
  Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

  # Hack to ensure we have indexes
  Dir.glob(File.join(WorkflowServer::Config.root, "lib", "workflow_server", "models", "**", "*.rb")).map do |file|
    begin
      model = "WorkflowServer::Models::#{file.match(/.+\/(?<model>.*).rb$/)['model'].camelize}"
      klass = model.constantize
      klass.create_indexes
      $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : created indexes for class #{klass}"
    rescue NameError, LoadError
      $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] ERROR -- : failed to create index for file #{file}"
    end
  end
end