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

  context "GET /activities/search" do
    before do
      node # Make sure the node is created
      wf_1 = FactoryGirl.create(
        :workflow_with_node,
        user: user,
        created_at: Time.now - 1.hour,
        subject: { class: "FooModel", id: 1 }
      )
      wf_2 = FactoryGirl.create(
        :workflow_with_node,
        user: user,
        created_at: Time.now - 1.hour,
        subject: { class: "BarModel", id: 2 }
      )

      node.update_attributes(created_at: 1.hour.ago)
      wf_1.nodes.first.update_attributes(created_at: 2.hours.ago)
      wf_2.nodes.first.update_attributes(created_at: 3.hours.ago)
    end

    it "returns nothing if no params are provided" do
      response = get "activities/search"
      expect(response.body).to eq("[]")
    end

    it "returns all nodes in server_status matching queried status" do
      Backbeat::StateManager.transition(node, current_server_status: :ready)
      Backbeat::StateManager.transition(node, current_server_status: :started)

      response = get "activities/search?current_status=started"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(node.id)
    end

    it "returns all nodes in client_status matching queried status" do
      Backbeat::StateManager.transition(node, current_client_status: :received)

      response = get "activities/search?current_status=received"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(node.id)
    end

    it "returns all nodes with past status matching queried status" do
      Backbeat::StateManager.transition(node, current_client_status: :received)
      Backbeat::StateManager.transition(node, current_client_status: :processing)

      response = get "activities/search?past_status=received"
      result = JSON.parse(response.body)

      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(node.id)
    end

    it "returns all nodes with matching name" do
      node.update_attributes!(name: "amazing")
      response = get "activities/search?name=amazing"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
    end

    it "returns nodes that were created in a certain timeframe" do
      node.status_changes.create({
        from_status: :pending,
        to_status: :errored,
        status_type: :current_server_status,
        created_at: 3.hours.ago.utc
      })
      node.status_changes.create({
        from_status: :pending,
        to_status: :errored,
        status_type: :current_server_status,
        created_at: 2.hours.ago.utc
      })

      status_start = 4.hours.ago.utc.iso8601
      status_end = 1.hours.ago.utc.iso8601
      query_params = "status_start=#{status_start}&status_end=#{status_end}"
      response = get "activities/search?#{query_params}"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(node.id)
    end

    it "returns all nodes partially matching on metadata" do
      uuid = SecureRandom.uuid
      node.client_node_detail.update_attributes!(metadata: { place_uuid: uuid })

      response = get "activities/search?metadata=#{uuid}"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(node.id)
    end

    it "returns results limited by per_page" do
      response = get "activities/search?per_page=2"
      result = JSON.parse(response.body)

      expect(result.count).to eq(2)
    end

    it "paginates results" do
      response = get "activities/search?per_page=2&page=2"
      result = JSON.parse(response.body)

      expect(result.count).to eq(1)
    end

    it "paginates results by last record id" do
      response = get "activities/search?per_page=2"
      first_page_result = JSON.parse(response.body)

      after_id = first_page_result[1]["id"]

      response = get "activities/search?per_page=2&last_id=#{after_id}"
      result = JSON.parse(response.body)

      expect(result.first["subject"]["id"]).to eq(2)
      expect(result.first["subject"]["class"]).to eq("BarModel")
    end
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

      it "creates nodes for different clients" do
        parent_node = workflow.children.first
        client_B = FactoryGirl.create(:user, name: "Client B", activity_endpoint: 'http://clientb.org')
        activity = {
          name: "Other client activity",
          client_id: client_B.id
        }
        activity_to_post = { "decisions" => [activity] }

        post "#{path}/#{parent_node.id}/decisions", activity_to_post
        activity_node = parent_node.children.first

        expect(activity_node.user_id).to eq(client_B.id)
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

    context "PUT #{path}/:id/schedule" do
      require 'support/sidekiq_helper'

      it "schedules the next ready child activity for the node" do
        child = FactoryGirl.create(
          :node,
          user: user,
          workflow: workflow,
          parent: node,
          current_server_status: :ready,
          current_client_status: :ready
        )

        put "#{path}/#{node.id}/schedule"
        SidekiqHelper.soft_drain

        expect(child.reload.current_server_status).to eq("started")
      end
    end

    context "PUT #{path}/:id/shutdown" do
      it "deactivates the node and following siblings" do
        sibling = FactoryGirl.create(
          :node,
          user: user,
          workflow: workflow,
          parent: node.parent,
          current_server_status: :ready,
          current_client_status: :ready
        )

        put "#{path}/#{node.id}/shutdown"

        expect(node.reload.current_server_status).to eq("deactivated")
        expect(sibling.reload.current_server_status).to eq("deactivated")
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

    context "GET #{path}/:id/status_changes" do
      it "returns all status changes" do
        node.status_changes.create({
          from_status: "pending",
          to_status: "ready",
          status_type: "current_server_status",
        })
        node.status_changes.create({
          from_status: "ready",
          to_status: "started",
          status_type: "current_server_status",
        })

        response = get "#{path}/#{node.id}/status_changes"
        body = JSON.parse(response.body)

        expect(body.first["toStatus"]).to eq "ready"
        expect(body.last["toStatus"]).to eq "started"
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
