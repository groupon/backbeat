require 'active_support/cache/redis_store'
require 'sidekiq'

module Backbeat
  Cache = ActiveSupport::Cache::RedisStore.new({
    pool: Sidekiq.redis_pool,
    namespace: Config.redis[:namespace]
  })
end
