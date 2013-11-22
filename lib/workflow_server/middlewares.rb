# encoding: utf-8
module WorkflowServer
  module Middlewares
    require_relative 'middlewares/sidekiq/transaction_id'
  end
end