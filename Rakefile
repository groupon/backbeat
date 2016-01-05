require 'rake'

if defined?(TorqueBox)
  require 'torquebox-rake-support'
end

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

task :env do
  require File.expand_path('../config/environment',  __FILE__)
end

namespace :db do
  require "active_record"
  require "foreigner"

  desc "drops and recreates the db"
  task :reset => :env do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.recreate_database(DB.config['database'], DB.config)
    end
  end

  desc "drop the db"
  task :drop => :env do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.drop_database(DB.config['database'])
    end
  end

  desc "create the db"
  task :create => :env do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.create_database(DB.config['database'], DB.config)
    end
  end

  desc "create the db if it doesn't already exist"
  task :create_if_not_exists => :env do
    DB.with_connection('database' => 'postgres') do |connection|
      connection.execute("CREATE DATABASE IF NOT EXISTS #{DB.config['database']}")
    end
  end

  desc "migrate the db"
  task :migrate => :env do
    DB.with_connection do |c|
      Foreigner.load
      ActiveRecord::Migrator.migrate('db/migrations', nil)
    end
  end

  desc "rollback one migration"
  task :rollback => :env do
    DB.with_connection do |c|
      ActiveRecord::Migrator.rollback('db/migrations')
    end
  end

  desc "seed the db for development testing"
  task :seed => :env do
    return unless Backbeat::Config.environment == 'development'
    load File.expand_path('../script/seed.rb', __FILE__)
  end

  namespace :schema do
    task :dump => :env do
      require 'active_record/schema_dumper'
      DB.with_connection do |c|
        File.open('db/schema.rb', 'w:utf-8') do |file|
          ActiveRecord::SchemaDumper.dump(c, file)
        end
      end
    end
  end
end

namespace :app do
  task :routes => :env do
    require 'backbeat/web'

    Backbeat::Web::API.routes.each do |api|
      method = api.route_method.ljust(10)
      path = api.route_path
      puts "     #{method} #{path}"
    end
  end
end

task :console do
  require_relative 'script/console'
end

task :add_user do
  require_relative 'script/add_user'
end
