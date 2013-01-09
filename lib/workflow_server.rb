# -*- encoding : utf-8 -*-

require_relative 'workflow_server/config'
require_relative 'workflow_server/errors'

module WorkflowServer
  autoload :Events,    'workflow_server/models/events'
  autoload :Manager,   'workflow_server/manager'
  autoload :Models,    'workflow_server/models'
  autoload :Version,   'workflow_server/version'
end