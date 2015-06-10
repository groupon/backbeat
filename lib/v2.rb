require "v2/helpers/instrument"
require "v2/events"
require "v2/client"
require "v2/schedulers"
require "v2/server"
require "v2/state_manager"
require "v2/workflow_tree"
require "v2/api"
require "v2/workers/async_worker"
require 'v2/models/user'
require 'v2/models/node'
require 'v2/models/node_detail'
require 'v2/models/client_node_detail'
require 'v2/models/status_change'
require 'v2/models/workflow'
require "workflow_server/logger"

module V2
  class Logger
    include WorkflowServer::Logger
  end

  class InvalidStatusChange < StandardError; end
  class InvalidServerStatusChange < InvalidStatusChange; end
  class InvalidClientStatusChange < InvalidStatusChange
    attr_reader :data

    def initialize(message, data = {})
      @data = data
      super(message)
    end
  end

  class WorkflowComplete < StandardError; end
end
