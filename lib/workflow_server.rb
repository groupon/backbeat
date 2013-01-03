# -*- encoding : utf-8 -*-

require 'mongoid'
require 'mongoid-locker'
require 'delayed_job_mongoid'

require 'accounting-utility'
require_relative 'workflow_server/errors'
require_relative 'workflow_server/events'
require_relative 'workflow_server/manager'
require_relative 'workflow_server/models'
require_relative 'workflow_server/version'

module WorkflowServer
  extend Accounting::Utility::ModuleSupport::AccountingModuleBase

  module AsyncClient

    def self.perform_activity(id)
      self.parent::AccountingServiceClient.ActivityWorker.enqueue(id)
    end

    def self.make_decision(decider_klass, id, subject_type, subject_id)
      self.parent::AccountingServiceClient.DecisionWorker.enqueue(decider_klass, id, subject_type, subject_id)
    end

  end

end
