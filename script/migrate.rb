require 'active_record'
require 'foreigner'
require 'ap'
config = YAML::load(IO.read('config/database.yml'))
ActiveRecord::Base.establish_connection config['development']
Foreigner.load
ActiveRecord::Migrator.migrate('migrations', nil)

