#!/usr/bin/env rake

require_relative 'app'
require 'rake'


namespace :mongo do
  task :create_indexes do |task|
    mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, "config", "mongoid.yml"))
    Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

    WorkflowServer::Models.constants.each do |klass|
      begin
        constant = "WorkflowServer::Models::#{klass}".constantize
        if constant.respond_to? :create_indexes
          constant.create_indexes
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : created indexes for class #{constant}"
        else
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : skipped creating indexes for class #{constant}"
        end
      rescue NameError, LoadError
        $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] ERROR -- : failed to create indexes for constant #{klass}"
      end
    end
  end

  task :remove_indexes do |task|
    mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, "config", "mongoid.yml"))
    Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

    WorkflowServer::Models.constants.each do |klass|
      begin
        constant = "WorkflowServer::Models::#{klass}".constantize
        if constant.respond_to? :remove_indexes
          constant.remove_indexes
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : removed indexes for class #{constant}"
        else
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : skipped removing indexes for class #{constant}"
        end
      rescue NameError, LoadError
        $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] ERROR -- : failed to remove indexes for constant #{klass}"
      end
    end
  end
end