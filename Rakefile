#!/usr/bin/env rake

require_relative 'app'
require 'rake'
require 'torquebox-rake-support'

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

namespace :roller do
  desc "build a new roller package.  pass PACKAGE=<package_name> on cl"
  task :build_package do
    package_name = ENV['PACKAGE']
    local_package_location = "config/roller/#{package_name}/"

    if package_name.nil? || package_name.empty?
      puts "Please specify PACKAGE=package_name on command line"
      exit 1
    elsif !Dir.exists?(local_package_location)
      puts "Can't find #{package_name} under config/roller"
      exit 2
    end

    date_ext = Time.now.strftime("%Y.%m.%d_%H.%M")
    dirname = "#{package_name}-#{date_ext}"
    filename = "#{dirname}.tar.gz"
    system("rsync -a #{local_package_location} /tmp/#{dirname}; cd /tmp; gnutar zcf #{filename} #{dirname}")
    system("rsync -a --stats --progress /tmp/#{filename} dev1.snc1:#{filename}")
    system("ssh dev1.snc1 publish_encap #{filename}")

    puts "created roller package named: #{dirname}"
  end
end
namespace :documentation do
  desc "update documentation at https://services.groupondev.com"
  task :update_service_discovery do
    require "#{File.join(File.expand_path(File.dirname(__FILE__)), 'app')}"
    require 'service_discovery/generation/generator'

    resource_schema = ServiceDiscovery::Generation::Generator.generate_grape_documentation(WorkflowServer::Config.root + "/doc/service-discovery/resources.json", /.*/, File.expand_path("public/resources.json"), Api)

    FileUtils.mkdir_p("public")
    File.open("public/resources.json", "w") { |f| f.print resource_schema }

    local_port = 8765

    # create a ssh tunnel to go to service-discovery.west host through b.west.groupon.com
    system("ssh -f -N -L #{local_port}:service-discovery.west:80 b.west.groupon.com > /dev/null 2>&1")

    response = HTTParty.post( "http://localhost:#{local_port}/services/backbeat",
                              body: {schema: JSON.parse(resource_schema)}.to_json,
                              headers: {"Content-Type" => "application/json"})

    raise "looks like the http request failed - code(#{response.code}), body(#{response.body})" if response.code != 200 || response.body != " "
  end
end
namespace :squash do
  desc "Notifies Squash that this server has received a new deploy."
  task :notify do
    require 'socket'
    Squash::Ruby.notify_deploy WorkflowServer::Config.environment,
                               ENV['REVISION']   || Squash::Ruby.current_revision,
                               ENV['HOST']       || Socket.gethostname
  end
end

namespace :sidekiq do
  desc "configures logging for our sidekiq workers"
  task :logging_setup do
    sidekiq.logger = WorkflowServer::SidekiqLogger
  end
end

task "sidekiq:setup" => "sidekiq:logging_setup"
