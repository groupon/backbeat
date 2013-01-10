# -*- encoding : utf-8 -*-
require_relative 'workflow_server/errors'

module WorkflowServer
  autoload :Manager,       'workflow_server/manager'
  autoload :Models,        'workflow_server/models'
  autoload :Version,       'workflow_server/version'
  autoload :AsyncClient,   'workflow_server/async_client'
end
