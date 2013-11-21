# encoding: utf-8
require 'workflow_server/logger'

module WorkflowServer
  module Middlewares
    class TransactionId
      def call(*args)
        WorkflowServer::Logger.tid(:set)
        yield
      ensure
        WorkflowServer::Logger.tid(:clear)
      end
    end
  end
end