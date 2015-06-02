def establish_readonly_connection
  ActiveRecord::Base.class_eval do
    def readonly?() true end
  end
  IRB.CurrentContext.irb_name = "[PROD-RO]"
  readonly_db_config = YAML::load_file("#{File.dirname(__FILE__)}/config/database.yml")["production_readonly"]
  if readonly_db_config
    ActiveRecord::Base.establish_connection(readonly_db_config)
    ActiveRecord::Base.connection.reset!
  else
    raise "No production readonly database defined in database.yml"
  end
end

def establish_write_connection
  ActiveRecord::Base.class_eval do
    def readonly?() false end
  end
  IRB.CurrentContext.irb_name = "irb"
  default_db_config = YAML::load_file("#{File.dirname(__FILE__)}/config/database.yml")[Backbeat.env]
  ActiveRecord::Base.establish_connection(default_db_config)
  ActiveRecord::Base.connection.reset!
end

# prints running workers counted by queue and host
def sidekiq_job_count
  Sidekiq::Workers.new.group_by { |a| a.first.split(":")[0] + " " + a.second["queue"]}.each_pair { |a,b| puts "#{a} - #{b.count}" };1
end