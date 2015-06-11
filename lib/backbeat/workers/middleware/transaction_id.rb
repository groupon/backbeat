require 'backbeat'

module Backbeat
  module Workers
    module Middleware
      class TransactionId
        def call(*args)
          Backbeat::Logging.tid(:set)
          yield
        ensure
          Backbeat::Logging.tid(:clear)
        end
      end
    end
  end
end
