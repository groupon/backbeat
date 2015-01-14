require "workflow_server/logger"

module V2
  class Logger
    include WorkflowServer::Logger
  end

  class InvalidEventStatusChange < StandardError; end
end

require "v2/models"
require "v2/server"
require "v2/processors"
