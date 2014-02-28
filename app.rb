ENV['ELASTICSEARCH_URL'] = 'http://accounting-ops1.snc1:9200'

require 'rubygems'
require 'bundler/setup'

$: << File.expand_path(File.join(__FILE__, '..', 'lib'))

require 'newrelic_rpm'
require 'awesome_print'
require 'tzinfo'
require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'
require 'delayed_job_monkey_patch'
require 'mongoid_indifferent_access'
require 'uuidtools'
require 'service-discovery'
require 'grape'
require 'api'
require 'workflow_server'
require 'sidekiq'
require 'kiqstand'

Squash::Ruby.configure(WorkflowServer::Config.squash_config)

# Sidekiq workers use this to pick up jobs and unicorn and delayed job workers need to be able to put stuff into redis
redis_config = YAML::load_file("#{File.dirname(__FILE__)}/config/redis.yml")[WorkflowServer::Config.environment.to_s]

Sidekiq.configure_client do |config|
  # We set the namespace to resque so that we can use all of the resque monitoring tools to monitor sidekiq too
  config.redis = { namespace: 'fed_sidekiq', size: 100, url: "redis://#{redis_config['host']}:#{redis_config['port']}" }
end

mongo_path = File.expand_path(File.join(WorkflowServer::Config.root, 'config', 'mongoid.yml'))
Mongoid.load!(mongo_path, WorkflowServer::Config.environment)

# set default priority to 2, since this is what we do in the delayed job worker.
# We have a mix of priorities in mongo right now with http and sidekiq workers
# creating jobs with priority 0 and delayed job worker creating jobs with priorty 2
# this will ensure all jobs get priority 2 and we will wait for the remaining 2.5 million
# jobs with priority 0 to slowly phase out. (** Lower numbers have higher priority **)
Delayed::Worker.default_priority = 2

puts "********** environment is #{WorkflowServer::Config.environment}"

############################################## MONKEY-PATCH ################################################
## FIX JRUBY TIME MARSHALLING - SEE https://github.com/rails/rails/issues/10900 ############################
# require 'active_support/core_ext/time/marshal' # add crappy marshalling first and then overwrite it

class Time
  class << self
    alias_method :_load_without_zone, :_load unless method_defined?(:_load_without_zone)
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

  alias_method :_dump_without_zone, :_dump unless method_defined?(:_dump_without_zone)
  def _dump(*args)
    obj = dup
    obj.instance_variable_set('@_isdst_and_zone', [dst?, zone])
    obj.send :_dump_without_zone, *args
  end
end

############################################### MONKEY-PATCH OVER ############################################
