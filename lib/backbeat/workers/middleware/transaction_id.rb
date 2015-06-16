require 'backbeat'

module Backbeat
  module Workers
    module Middleware
      class TransactionId
        def call(*args)
          Backbeat::Logger.tid(:set)
          yield
        ensure
          Backbeat::Logger.tid(:clear)
        end
      end
    end
  end
end
