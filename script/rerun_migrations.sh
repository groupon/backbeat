dropdb backbeat && createdb backbeat 
psql backbeat
CREATE ROLE backbeat with LOGIN CREATEDB SUPERUSER;


bin/console
require 'active_record'
require 'foreigner'
config = YAML::load(IO.read('config/database.yml'))
ActiveRecord::Base.establish_connection config['development']
Foreigner.load
ActiveRecord::Migrator.migrate('migrations', nil)


