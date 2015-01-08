require "workflow_server"

module Api
  module WorkflowHelper
    def find_workflow(id)
      wf = current_user.workflows.find(id)
      raise WorkflowServer::EventNotFound, "Workflow with id(#{id}) not found" unless wf
      wf
    end
  end
end
