require 'active_record'
config = YAML::load(IO.read('config/database.yml'))
ActiveRecord::Base.establish_connection config['development'].merge('database' => nil)
ActiveRecord::Base.connection.create_database config['development']['database'],  {:charset => 'utf8', :collation => 'utf8_unicode_ci'}




require 'active_record'
require 'foreigner'
config = YAML::load(IO.read('config/database.yml'))
ActiveRecord::Base.establish_connection config['development']
Foreigner.load
ActiveRecord::Migrator.migrate('migrations', nil)


class Node < ActiveRecord::Base
  include ::UUIDSupport

  before_create do
    self.id = UUIDTools::UUID.random_create.to_s
  end
end

module V2
  class Workflow < ActiveRecord::Base
    self.table_name = :workflows
  end

  before_create do
    self.id = UUIDTools::UUID.random_create.to_s
  end
end
