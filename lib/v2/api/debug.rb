require "grape"
require "v2/models/node"
require "v2/models/workflow"
require "api/helpers/current_user_helper"

module V2
  module Api
    class Debug < Grape::API
      helpers ::Api::CurrentUserHelper
      version 'v2', using: :path

      get "/debug/error_workflows" do
        workflow_ids = Node.where(
          user_id: current_user.id,
          current_client_status: :errored
        ).pluck(:workflow_id).uniq

        Workflow.where("id IN (?)", workflow_ids)
      end
    end
  end
end
