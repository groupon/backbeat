require 'active_support/cache/redis_store'

module Backbeat
  Cache = ActiveSupport::Cache::RedisStore.new(Config.redis.merge(pool_size: 5))
end
