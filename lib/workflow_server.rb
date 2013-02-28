# -*- encoding : utf-8 -*-
require 'workflow_server/config'
require 'workflow_server/logger'
require 'workflow_server/helper'
require 'workflow_server/errors'
require 'workflow_server/async'
require 'workflow_server/models'
require 'workflow_server/client'
require 'workflow_server/reports'
require 'workflow_server/version'

module WorkflowServer
  class << self

    def schedule_next_decision(workflow)
      workflow.with_lock do
        if workflow.decisions.not_in(:status => [:complete, :open]).empty?
          if (next_decision = workflow.decisions.where(status: :open).first)
            next_decision.start
          end
        end
      end
    end

    def get_event(id)
      Models::Event.find(id)
    end

    # options include workflow_type: workflow_type, subject: subject, decider: decider, name: workflow_type, user: user
    WORKFLOW_ATTRIBUTES = [:subject, :workflow_type, :decider, :name, :user].freeze
    def find_or_create_workflow(options = {})
      attributes = {}
      WORKFLOW_ATTRIBUTES.each { |k| attributes[k] = options[k] }
      attributes[:name] ||= attributes[:workflow_type]

      workflow = Models::Workflow.find_or_create_by(attributes)
      workflow.save
      workflow
    end
  end
end
