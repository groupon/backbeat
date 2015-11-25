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
require 'helper/request_helper'

describe Backbeat::Web::WorkflowsAPI, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    allow(Backbeat::Client).to receive(:make_decision)
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "POST /workflows" do
    it "returns 201 and creates a new workflow when all parameters present" do
      workflow_data = {
        workflow_type: "WFType",
        subject: { subject_klass: "PaymentTerm", subject_id: 100 },
        decider: "PaymentDecider"
      }
      response = post 'v2/workflows', workflow_data

      expect(response.status).to eq(201)

      first_response = JSON.parse(response.body)
      workflow = Backbeat::Workflow.find(first_response['id'])

      expect(workflow.subject).to eq({ "subject_klass" => "PaymentTerm", "subject_id" => "100" })
      expect(workflow.name).to eq("WFType")

      response = post 'v2/workflows', workflow_data
      expect(first_response['id']).to eq(JSON.parse(response.body)['id'])
    end

    it "returns 201 and creates a new workflow when all parameters present using name parameter" do
      workflow_data = {
        name: "WFName",
        subject: { subject_klass: "PaymentTerm", subject_id: 100 },
        decider: "PaymentDecider"
      }
      response = post 'v2/workflows', workflow_data

      expect(response.status).to eq(201)

      first_response = JSON.parse(response.body)
      workflow = Backbeat::Workflow.find(first_response['id'])

      expect(workflow.subject).to eq({ "subject_klass" => "PaymentTerm", "subject_id" => "100" })
      expect(workflow.name).to eq("WFName")

      response = post 'v2/workflows', workflow_data
      expect(first_response['id']).to eq(JSON.parse(response.body)['id'])
    end
  end

  context "POST /workflows/:id/signal" do
    let(:signal_params) {{
      name: 'Signal #1',
      options: {
        client_data: { data: 'abc' },
        metadata: { metadata: '123'}
      }
    }}

    it "creates a signal on the workflow" do
      response = post "v2/workflows/#{workflow.id}/signal", signal_params

      expect(response.status).to eq(201)
      expect(workflow.children.count).to eq(2)
      expect(workflow.children.last.name).to eq('Signal #1')
      expect(workflow.children.last.client_data).to eq({ 'data' => 'abc' })
      expect(workflow.children.last.client_metadata).to eq({ 'metadata' => '123' })
    end

    it "calls schedule next node after creating the signal" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, workflow)

      response = post "v2/workflows/#{workflow.id}/signal", signal_params
    end

    it "returns a 400 response if the workflow is complete" do
      workflow.complete!
      expect(workflow.children.count).to eq(1)

      response = post "v2/workflows/#{workflow.id}/signal", signal_params

      expect(response.status).to eq(400)
      expect(workflow.children.count).to eq(1)
    end
  end

  context "POST /workflows/:id/signal/:name" do
    let(:signal_params) {{
      options: {
        client_data: { data: '123' },
        metadata: { metadata: '456'}
      }
    }}

    it "creates a signal on the workflow" do
      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params

      expect(response.status).to eq(201)
      expect(workflow.children.count).to eq(2)
      expect(workflow.children.last.name).to eq('new_signal')
      expect(workflow.children.last.client_data).to eq({ 'data' => '123' })
      expect(workflow.children.last.client_metadata).to eq({ 'metadata' => '456' })
    end

    it "calls schedule next node after creating the signal" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, workflow)

      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params
    end

    it "returns a 400 response if the workflow is complete" do
      workflow.complete!
      expect(workflow.children.count).to eq(1)

      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params

      expect(response.status).to eq(400)
      expect(workflow.children.count).to eq(1)
    end

    it "adds the link_id to the signal node" do
      response = post "v2/workflows/#{workflow.id}/signal/test", { options: { parent_link_id: node.id } }
      expect(workflow.nodes.last.parent_link).to eq(node)
    end
  end

  context "GET /workflows/search" do
    let(:ids) { Array.new(3) { SecureRandom.uuid }.sort.reverse }
    let!(:wf_1) { FactoryGirl.create(
      :workflow,
      id: ids.first,
      user: user,
      subject: { class: "FooModel", id: 1 },
      name: "import"
    )}

    let!(:wf_2) { FactoryGirl.create(
      :workflow,
      id: ids.second,
      user: user,
      subject: { class: "BarModel", id: 2 },
      name: "import"
    )}

    let!(:wf_3) { FactoryGirl.create(
      :workflow,
      id: ids.last,
      user: user,
      subject: { class: "FooModel", id: 3 },
      name: "export"
    )}

    it "returns all workflows with matching name" do
      response = get "v2/workflows/search?name=import"
      result = JSON.parse(response.body)
      expect(result.count).to eq(2)
      expect(result.map{ |wf| wf["name"] }).to_not include("bar")
    end

    it "returns all workflows partially matching on subject" do
      response = get "v2/workflows/search?subject=FooModel"
      result = JSON.parse(response.body)
      expect(result.count).to eq(2)
      expect(result.first["id"]).to eq(wf_1.id)
      expect(result.last["id"]).to eq(wf_3.id)
    end

    it "returns all workflows matching name and partial subject" do
      response = get "v2/workflows/search?subject=FooModel&name=import"
      result = JSON.parse(response.body)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns all workflows with nodes in server_status matching queried status" do
      errored_node = FactoryGirl.create(
        :node,
        workflow: wf_1,
        user: user,
        current_server_status: :errored
      )
      response = get "v2/workflows/search?current_status=errored"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns all workflows with nodes in client_status matching queried status" do
      errored_node = FactoryGirl.create(
        :node,
        workflow: wf_1,
        user: user,
        current_client_status: :errored
      )
      response = get "v2/workflows/search?current_status=errored"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns workflows filtered by all params" do
      errored_node = FactoryGirl.create(
        :node,
        workflow: wf_1,
        user: user,
        current_client_status: :pending
      )
      response = get "v2/workflows/search?current_status=pending&name=import&subject=FooModel"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns workflows with nodes that errored in a certain timeframe" do
      errored_node = FactoryGirl.create(
        :node,
        workflow: wf_1,
        user: user,
        current_client_status: :pending
      )
      errored_node.status_changes.create({
        from_status: :pending,
        to_status: :errored,
        status_type: :current_server_status,
        created_at: 2.hours.ago.utc
      })

      status_start = 3.hours.ago.utc.iso8601
      status_end = 1.hours.ago.utc.iso8601
      query_params = "status_start=#{status_start}&status_end=#{status_end}&past_status=errored"
      response = get "v2/workflows/search?#{query_params}"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns workflows with errors that are now complete" do
      errored_node = FactoryGirl.create(
        :node,
        workflow: wf_1,
        user: user,
        current_client_status: :complete
      )
      errored_node.status_changes.create({
        from_status: :sent_to_client,
        to_status: :errored,
        status_type: :current_client_status,
        created_at: 1.hours.ago.utc
      })

      response = get "v2/workflows/search?current_status=complete&past_status=errored"
      result = JSON.parse(response.body)
      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_1.id)
    end

    it "returns nothing if no params are provided" do
      response = get "v2/workflows/search"
      expect(response.body).to eq("[]")
    end

    it "returns results limited by per_page" do
      response = get "v2/workflows/search?subject=Model&per_page=2"
      result = JSON.parse(response.body)

      expect(result.count).to eq(2)
    end

    it "paginates results" do
      response = get "v2/workflows/search?subject=Model&per_page=2&page=2"
      result = JSON.parse(response.body)

      expect(result.count).to eq(1)
      expect(result.first["id"]).to eq(wf_3.id)
    end

    it "defaults pagination to 25 results" do
      response = get "v2/workflows/search?subject=Model"
      result = JSON.parse(response.body)

      expect(result.count).to eq(3)
    end

    it "paginates results by last record id" do
      uuids = Array.new(2) { SecureRandom.uuid }.sort.reverse
      wf_4 = FactoryGirl.create(
        :workflow,
        id: uuids.first,
        user: user,
        subject: { class: "FooModel", id: 4 },
        name: "export",
        created_at: Time.now - 1.hour
      )

      wf_5 = FactoryGirl.create(
        :workflow,
        id: uuids.last,
        user: user,
        subject: { class: "FooModel", id: 5 },
        name: "export",
        created_at: Time.now - 1.hour
      )


      response = get "v2/workflows/search?subject=Model&per_page=2&last_id=#{wf_2.id}"
      result = JSON.parse(response.body)

      expect(result.count).to eq(2)
      expect(result.first["id"]).to eq(wf_3.id)
      expect(result.last["id"]).to eq(wf_4.id)
    end
  end

  context "GET /workflows/:id" do
    it "returns a workflow given an id" do
      response = get "v2/workflows/#{workflow.id}"
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(workflow.id)
    end
  end

  context "GET /workflows/:id/children" do
    it "returns the workflows immediate" do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: workflow,
        user: user
      )

      response = get "v2/workflows/#{workflow.id}/children"
      expect(response.status).to eq(200)

      body = JSON.parse(response.body)
      children = workflow.children

      expect(body.first["id"]).to eq(children.first.id)
      expect(body.second["currentServerStatus"]).to eq(children.second.current_server_status)
      expect(body.count).to eq(2)
    end
  end

  context "GET /workflows/:id/nodes" do
    before do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: workflow,
        user: user
      )
      @third_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: second_node,
        user: user,
        current_server_status: :complete
      )
      @third_node.client_node_detail.update_attributes!(metadata: {"version"=>"v2", "workflow_type_on_v2"=>true})
    end

    it "returns the workflows nodes in ClientNodeSerializer" do
      response = get "v2/workflows/#{workflow.id}/nodes"
      expect(response.status).to eq(200)

      body = JSON.parse(response.body)
      nodes = workflow.nodes

      expect(body.first["id"]).to eq(nodes.first.id)
      expect(body.second["id"]).to eq(nodes.second.id)
      expect(body.third["id"]).to eq(nodes.third.id)
      expect(body.third["currentServerStatus"]).to eq(nodes.third.current_server_status)
      expect(body.third["metadata"]).to eq({"version"=>"v2", "workflowTypeOnV2"=>true})
      expect(body.count).to eq(3)
    end

    it "returns nodes limited by query" do
      response = get "v2/workflows/#{workflow.id}/nodes?currentServerStatus=complete"
      expect(response.status).to eq(200)

      body = JSON.parse(response.body)
      expect(body.first["id"]).to eq(@third_node.id)
      expect(body.count).to eq(1)
    end
  end

  context "GET /workflows/:id/tree" do
    it "returns the workflow tree as a hash" do
      response = get "v2/workflows/#{workflow.id}/tree"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(workflow.id.to_s)
    end
  end

  context "GET /workflows/:id/tree/print" do
    it "returns the workflow tree as a string" do
      response = get "v2/workflows/#{workflow.id}/tree/print"
      body = JSON.parse(response.body)

      expect(body["print"]).to include(workflow.name)
    end
  end

  context "PUT /workflows/:id/complete" do
    it "marks the workflow as complete" do
      response = put "v2/workflows/#{workflow.id}/complete"

      expect(response.status).to eq(200)
      expect(workflow.reload.complete?).to eq(true)
    end
  end

  context "PUT /workflows/:id/pause" do
    it "marks the workflow as paused" do
      response = put "v2/workflows/#{workflow.id}/pause"

      expect(response.status).to eq(200)
      expect(workflow.reload.paused?).to eq(true)
    end
  end

  context "PUT /workflows/:id/resume" do
    it "resumes the workflow" do
      workflow.pause!

      response = put "v2/workflows/#{workflow.id}/resume"

      expect(response.status).to eq(200)
      expect(workflow.reload.paused?).to eq(false)
    end
  end

  context "GET /workflows" do
    let(:query) {{
      decider: workflow.decider,
      subject: workflow.subject.to_json,
      workflow_type: workflow.name
    }}

    it "returns the first workflow matching the decider and subject" do
      workflow.update_attributes(migrated: true)

      response = get "v2/workflows", query
      body = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(body["id"]).to eq(workflow.id)
    end

    [:decider, :subject, :workflow_type].each do |param|
      it "returns 404 if a workflow is not found by #{param}" do
        workflow.update_attributes(migrated: true)

        response = get "v2/workflows", query.merge(param => "Foo")

        expect(response.status).to eq(404)
      end
    end

    it "returns 404 if the workflow is not fully migrated" do
      workflow.update_attributes(migrated: false)

      response = get "v2/workflows", query

      expect(response.status).to eq(404)
    end
  end

  context "GET /names" do
    it "returns a list of all workflow names" do
      FactoryGirl.create(:workflow, { name: "B Workflow", user: user })
      FactoryGirl.create(:workflow, { name: "A Workflow", user: user })
      FactoryGirl.create(:workflow, { name: "C Workflow", user: user })

      response = get "/v2/workflows/names"
      body = JSON.parse(response.body)

      expect(body).to eq(["A Workflow", "B Workflow", "C Workflow"])
    end

    it "caches the results" do
      FactoryGirl.create(:workflow, { name: "B Workflow", user: user })
      FactoryGirl.create(:workflow, { name: "A Workflow", user: user })
      FactoryGirl.create(:workflow, { name: "C Workflow", user: user })
      response = get "/v2/workflows/names"
      body = JSON.parse(response.body)

      expect(body.size).to eq(3)

      FactoryGirl.create(:workflow, { name: "D Workflow", user: user })

      response = get "/v2/workflows/names"
      body = JSON.parse(response.body)

      expect(body.size).to eq(3)
    end
  end
end
