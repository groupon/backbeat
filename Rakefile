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
      ActiveRecord::Migrator.migrate('migrations', nil)
    end
  end

  desc "rollback one migration"
  task :rollback => :env do
    DB.with_connection do |c|
      ActiveRecord::Migrator.rollback('migrations')
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

namespace :license do
  task :add do
    license = File.readlines("./LICENSE")
    trailing_whitespace = /\s+\n$/
    commented_license = license.map do |line|
      "# #{line}".sub(trailing_whitespace, "\n")
    end.push("\n")

    Dir['lib/**/*.rb'].each do |path|
      file_content = File.readlines(path)
      if file_content.first != commented_license.first
        File.write(path, (commented_license + file_content).join)
        puts "Added license to #{path}"
      end
    end
  end
end
