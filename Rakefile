require File.expand_path('../config/environment',  __FILE__)
require 'rake'

if defined?(Torquebox)
  require 'torquebox-rake-support'
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
    env = Backbeat::Config.environment
    database_config = YAML::load(IO.read('config/database.yml'))
    @config ||= (database_config["#{env}_dba"] || database_config[env])
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

  desc "rollback one migration"
  task :rollback do
    DB.with_connection do |c|
      ActiveRecord::Migrator.rollback('migrations')
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
