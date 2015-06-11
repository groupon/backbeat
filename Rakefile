#!/usr/bin/env rake

require './app'
require 'rake'
require 'torquebox-rake-support'

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

namespace :sidekiq do
  desc "configures logging for our sidekiq workers"
  task :logging_setup do
    sidekiq.logger = WorkflowServer::SidekiqLogger
  end
end

task "sidekiq:setup" => "sidekiq:logging_setup"

require "active_record"
require "foreigner"

module DB
  def self.config
    migration_env = Backbeat.env == "production" ? "production_dba" : Backbeat.env
    @config ||= YAML::load(IO.read('config/database.yml'))[migration_env]
  end

  def self.with_connection(options = {})
    ActiveRecord::Base.establish_connection(config.merge(options))
    yield ActiveRecord::Base.connection
  end
end

namespace :db do
  desc "drops and recreates the db"
  task :reset do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.recreate_database(DB.config['database'], DB.config)
    end
  end

  desc "drop the db"
  task :drop do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.drop_database(DB.config['database'])
    end
  end

  desc "create the db"
  task :create do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.create_database(DB.config['database'], DB.config)
    end
  end

  desc "create the db if it doesn't already exist"
  task :create_if_not_exists do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.execute("CREATE DATABASE IF NOT EXISTS #{DB.config['database']}")
    end
  end

  desc "migrate the db"
  task :migrate do
    DB.with_connection do |c|
      Foreigner.load
      ActiveRecord::Migrator.migrate('migrations', nil)
    end
  end
end

namespace :app do
  task :routes do
    Backbeat::API.routes.each do |api|
      method = api.route_method.ljust(10)
      path = api.route_path
      puts "     #{method} #{path}"
    end
  end
end
