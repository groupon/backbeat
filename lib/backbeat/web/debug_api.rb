require 'grape'
require 'backbeat/models/node'
require 'backbeat/models/workflow'
require 'backbeat/web/helpers/current_user_helper'

module Backbeat
  module Web
    class DebugApi < Grape::API
      helpers CurrentUserHelper
      version 'v2', using: :path

      resource 'debug' do

        get "/error_workflows" do
          workflow_ids = Node.where(
            user_id: current_user.id,
            current_client_status: :errored
          ).pluck(:workflow_id).uniq

          Workflow.where("id IN (?)", workflow_ids)
        end

      end
    end
  end
end
