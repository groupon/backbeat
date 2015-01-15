require "v2/api"
require "v2/models"
require "v2/server"
require "v2/processors"
require "workflow_server/logger"

module V2
  class Logger
    include WorkflowServer::Logger
  end

  class InvalidEventStatusChange < StandardError; end
end
