# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'spec_helper'
require 'support/request_helper'

describe Backbeat::Web::ActivitiesAPI, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    allow(Backbeat::Client).to receive(:make_decision)
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  ['v2/events', '/activities'].each do |path|

    context "PUT #{path}/:id/restart" do
      context "with valid restart state" do
        before do
          node.update_attributes(
            current_client_status: :errored,
            current_server_status: :errored
          )
        end

        it "restarts the node" do
          response = put "#{path}/#{node.id}/restart"

          expect(node.reload.current_client_status).to eq("ready")
          expect(node.reload.current_server_status).to eq("ready")
        end

        it "removes an existing retry job" do
          expect(Backbeat::Workers::AsyncWorker).to receive(:remove_job).with(
            Backbeat::Events::RetryNode,
            node
          )

          put "#{path}/#{node.id}/restart"
        end
      end

      context "with invalid restart state" do
        it "returns 409" do
          response = put "#{path}/#{node.id}/restart"
          expect(response.status).to eq(409)
        end
      end

      context "when no node found for id" do
        it "returns a 404" do
          response = put "#{path}/#{SecureRandom.uuid}/restart"
          expect(response.status).to eq(404)
        end
      end
    end

    context "POST /#{path}/:id/decisions" do
      let(:parent_node) { workflow.children.first }

      it "creates the node detail with retry data" do
        activity = RequestHelper.client_activity_data({
          retry: 20,
          retry_interval: 50
        })
        activity_to_post = { "decisions" => [activity] }

        response = post "#{path}/#{parent_node.id}/decisions", activity_to_post
        activity_node = parent_node.children.first

        expect(JSON.parse(response.body).first).to eq(activity_node.id)
        expect(activity_node.node_detail.retry_interval).to eq(50)
        expect(activity_node.node_detail.retries_remaining).to eq(20)
        expect(activity_node.client_metadata).to eq({"version"=>"v2"})
        expect(activity_node.client_data).to eq({"params" => [{"firstName" => "John", "lastName" => "Smith"}, "123"]})
      end

      it "handles the legacy 'args' param" do
        activity = RequestHelper.client_activity_data({
          retry: 20,
          retry_interval: 50
        })
        activity_to_post = { "args" => { "decisions" => [activity] }}

        post "#{path}/#{parent_node.id}/decisions", activity_to_post

        expect(parent_node.children.count).to eq(1)
      end

      it "returns a 401 response if the auth token is not provided" do
        header "Authorization", ""

        response = post "#{path}/#{parent_node.id}/decisions", { decisions: [] }

        expect(response.status).to eq(401)
      end
    end

    context "GET /#{path}/:id" do
      it "returns the node data" do
        node = workflow.children.first
        response = get "#{path}/#{node.id}"
        body = JSON.parse(response.body)

        expect(body["id"]).to eq(node.id)
        expect(body["clientData"]).to eq(node.client_data)
      end

      it "returns 404 if the node does not belong to the user" do
        node = FactoryGirl.create(
          :workflow_with_node,
          user: FactoryGirl.create(:user, name: "New user")
        ).children.first

        response = get "workflows/#{node.workflow_id}/#{path}/#{node.id}"

        expect(response.status).to eq(404)
      end

      it "finds the node by id when no workflow id is provided" do
        node = workflow.children.first
        response = get "#{path}/#{node.id}"
        body = JSON.parse(response.body)

        expect(body["id"]).to eq(node.id)
      end

      it "returns 404 if the node does not belong to the workflow" do
        node = FactoryGirl.create(
          :workflow_with_node,
          name: :a_unique_name,
          user: workflow.user
        ).children.first

        response = get "workflows/#{workflow.id}/#{path}/#{node.id}"

        expect(response.status).to eq(404)
      end
    end

    context "PUT /#{path}/:id/status/processing" do
      it "fires the ClientProcessing event" do
        node.update_attributes(current_client_status: :received)
        put "#{path}/#{node.id}/status/processing"

        expect(node.reload.current_client_status).to eq("processing")
      end

      it "touches the node indicating client is working on it" do
        Backbeat::Config.options[:client_timeout] = 100
        node.update_attributes(current_client_status: :received)

        put "#{path}/#{node.id}/status/processing"

        node.node_detail.reload
        expect(node.node_detail.complete_by.to_s).to eq((Time.now.utc + 100).to_s)
      end

      it "returns an error with an invalid state change" do
        node.update_attributes(current_client_status: :processing)

        response = put "#{path}/#{node.id}/status/processing"
        body = JSON.parse(response.body)

        expect(response.status).to eq(409)
        expect(body["message"]).to eq("Cannot transition current_client_status from processing to processing")
        expect(body["currentStatus"]).to eq("processing")
        expect(body["attemptedStatus"]).to eq("processing")
      end

      it "does not mark the node in error state with invalid client state change" do
        node.update_attributes(current_client_status: :processing, current_server_status: :sent_to_client)

        response = put "#{path}/#{node.id}/status/processing"

        expect(node.reload.current_client_status).to eq("processing")
        expect(node.reload.current_server_status).to eq("sent_to_client")
      end

      it "does not mark the node in error state with invalid client state change" do
        node.update_attributes(current_client_status: :processing, current_server_status: :sent_to_client)

        response = put "#{path}/#{node.id}/status/processing"

        expect(node.reload.current_client_status).to eq("processing")
        expect(node.reload.current_server_status).to eq("sent_to_client")
      end
    end

    context "PUT /#{path}/:id/status/completed" do
      it "marks the node as complete" do
        node.update_attributes({
          current_server_status: :sent_to_client,
          current_client_status: :processing
        })
        client_params = { "result" => "Done", "error" => nil }

        put "#{path}/#{node.id}/status/completed", { "response" => client_params }
        node.reload

        expect(node.current_client_status).to eq("complete")
        expect(node.status_changes.last.response).to eq(client_params)
      end
    end

    context "PUT #{path}/:id/status/errored" do
      it "stores the client backtrace in the client node detail" do
        client_params = { "error" => { "backtrace" => "The backtrace" }}

        put "#{path}/#{node.id}/status/errored", { "response" => client_params }

        expect(node.status_changes.first.response).to eq(client_params)
      end
    end

    context "PUT #{path}/:id/reset" do
      it "deactivates all child nodes on the node" do
        child = FactoryGirl.create(:node, user: user, workflow: workflow, parent: node)

        put "#{path}/#{node.id}/reset"

        expect(node.children.count).to eq(1)
        expect(child.reload.current_server_status).to eq("deactivated")
      end
    end

    context "PUT #{path}/:id/status/deactivated" do
      it "deactivates previous nodes from the activity" do
        second_node = FactoryGirl.create(
          :node,
          workflow: workflow,
          parent: node,
          user: user
        )

        put "#{path}/#{second_node.id}/status/deactivated"

        expect(node.reload.current_server_status).to eq("deactivated")
      end
    end

    context "PUT #{path}/:id/canceled" do
      it "deactivates it self and all child nodes on the node" do
        child = FactoryGirl.create(:node, user: user, workflow: workflow, parent: node)

        put "#{path}/#{node.id}/status/canceled"

        expect(node.reload.current_server_status).to eq("deactivated")
        expect(child.reload.current_server_status).to eq("deactivated")
      end
    end

    context "GET #{path}/:id/errors" do
      it "returns all status changes to an errored state" do
        node.status_changes.create({
          from_status: "ready",
          to_status: "errored",
          status_type: "current_server_status",
          response: { error: { message: "Whoops" } }
        })
        node.status_changes.create({
          from_status: "pending",
          to_status: "ready",
          status_type: "current_server_status",
          response: { result: "Done" }
        })
        node.status_changes.create({
          from_status: "sent_to_client",
          to_status: "errored",
          status_type: "current_client_status",
          response: { error: { message: "An error" } }
        })

        response = get "#{path}/#{node.id}/errors"
        body = JSON.parse(response.body)

        expect(body.count).to eq(2)
        expect(body.first["response"]["error"]["message"]).to eq("Whoops")
        expect(body.second["response"]["error"]["message"]).to eq("An error")
      end
    end

    context "GET #{path}/:id/response" do
      it "returns the response for the last client status change" do
        node.status_changes.create({
          from_status: "sent_to_client",
          to_status: "errored",
          status_type: "current_client_status",
          response: { error: { message: "An error" } }
        })
        node.status_changes.create({
          from_status: "pending",
          to_status: "ready",
          status_type: "current_server_status"
        })

        response = get "#{path}/#{node.id}/response"
        body = JSON.parse(response.body)

        expect(body["error"]["message"]).to eq("An error")
      end
    end
  end
end
