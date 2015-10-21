require 'active_support/cache'

module Backbeat
  Cache = ActiveSupport::Cache::MemoryStore.new
end
