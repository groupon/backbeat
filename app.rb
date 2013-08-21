require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, "..", "lib"))

require 'awesome_print'
require 'mongoid'
require 'mongoid-locker'
require 'mongoid_auto_increment'
require 'delayed_job_mongoid'
require 'mongoid_indifferent_access'
require 'uuidtools'
require 'log4r'
require 'service-discovery'
require 'grape'
require 'api'
require 'workflow_server'
require 'resque'

Squash::Ruby.configure(WorkflowServer::Config.squash_config)

# Resque workers use this to pick up jobs, unicorn and delayed job workers need to be able to put stuff into redis
config = YAML::load_file("#{File.dirname(__FILE__)}/config/redis.yml")[ENV['RACK_ENV']]
Resque.redis = Redis.new(:host => config['host'], :port => config['port'])


require 'newrelic_rpm'



############################################## MONKEY-PATCH ################################################
## FIX JRUBY TIME MARSHALLING - SEE https://github.com/rails/rails/issues/10900 ############################
require 'active_support/core_ext/time/marshal' # add crappy marshalling first and then overwrite it

class Time
  class << self
    def _load(marshaled_time)
      time = _load_without_zone(marshaled_time)
      time.instance_eval do
        if isdst_and_zone = defined?(@_isdst_and_zone) && remove_instance_variable('@_isdst_and_zone')
          ary = to_a
          ary[0] += subsec if ary[0] == sec
          ary[-2, 2] = isdst_and_zone
          utc? ? Time.utc(*ary) : Time.local(*ary)
        else
          self
        end
      end
    end
  end

  def _dump(*args)
    obj = dup
    obj.instance_variable_set('@_isdst_and_zone', [dst?, zone])
    obj.send :_dump_without_zone, *args
  end
end

############################################### MONKEY-PATCH OVER ############################################