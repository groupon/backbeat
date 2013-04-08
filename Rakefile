#!/usr/bin/env rake

require_relative 'app'
require 'rake'

MODELS_TO_INDEX = [WorkflowServer::Models.constants.map{|model| "WorkflowServer::Models::#{model}"},
                   Delayed::Backend::Mongoid.constants.map{|model| "Delayed::Backend::Mongoid::#{model}"}].flatten

namespace :mongo do
  task :create_indexes do |task|
    mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, "config", "mongoid.yml"))
    Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

    MODELS_TO_INDEX.each do |model|
      begin
        constant = model.constantize
        if constant.respond_to? :create_indexes
          constant.add_indexes
          constant.create_indexes
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : created indexes for class #{constant}"
        else
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : skipped creating indexes for class #{constant}"
        end
      rescue NameError, LoadError
        $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] ERROR -- : failed to create indexes for constant #{model}"
      end
    end
  end

  task :remove_indexes do |task|
    mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, "config", "mongoid.yml"))
    Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

    MODELS_TO_INDEX.each do |model|
      begin
        constant = model.constantize
        if constant.respond_to? :remove_indexes
          constant.remove_indexes
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : removed indexes for class #{constant}"
        else
          $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] INFO -- : skipped removing indexes for class #{constant}"
        end
      rescue NameError, LoadError
        $stdout.puts "I, [#{Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")} \##{$$}] ERROR -- : failed to remove indexes for constant #{model}"
      end
    end
  end
end
