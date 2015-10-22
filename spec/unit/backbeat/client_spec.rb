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
require 'webmock/rspec'

describe Backbeat::Client do

  let(:user) { FactoryGirl.create(:user, notification_endpoint: "http://notifications.com/api/v1/workflows/notify_of") }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  context ".notify_of" do
    it "calls the notify of endpoint" do
      error = {"couldbe" => "anything"}
      notification_body = Backbeat::Client::HashKeyTransformations.camelize_keys(
        {
          "notification" => {
            "type" =>"Backbeat::Node",
            "id"=> node.id,
            "name" => node.name,
            "subject" => node.subject,
            "message" => "error",
          },
          "error" => error
        }
      )
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of")
        .with(body: notification_body.to_json)
        .to_return(status: 200, body: "", headers: {})

      Backbeat::Client.notify_of(node, "error", error)

      expect(WebMock).to have_requested(
        :post, "http://notifications.com/api/v1/workflows/notify_of"
      ).with(body: notification_body.to_json)
    end

    it "raises an http error unless response is between 200-299" do
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of").to_return(status: 404)
      expect {
        Backbeat::Client.notify_of(node, "error", nil)
      }.to raise_error(Backbeat::HttpError, "HTTP request for notification failed")
    end
  end

  context ".perform_action" do
    it "sends a call to make decision if the node is a legacy decision" do
      node.node_detail.legacy_type = 'decision'

      expect(Backbeat::Client).to receive(:make_decision) do |params, user|
        expect(params).to include(
          subject: node.subject,
          decider: node.decider,
          client_data: node.client_node_detail.data
        )
        expect(user).to eq(node.user)
      end

      Backbeat::Client.perform_action(node)
    end

    it "sends a call to perform activity if the node is a legacy activity" do
      node.node_detail.legacy_type = 'activity'

      expect(Backbeat::Client).to receive(:perform_activity) do |params, user|
        expect(params).to include(
          client_data: node.client_node_detail.data
        )
        expect(user).to eq(node.user)
      end

      Backbeat::Client.perform_action(node)
    end

    it "sends a call to perform activity if the client does not have a decision endpoint" do
      node.node_detail.legacy_type = 'decision'
      user.update_attributes!({ decision_endpoint: nil })

      expect(Backbeat::Client).to receive(:perform_activity) do |params, user|
        expect(params).to include(
          client_data: node.client_node_detail.data
        )
        expect(user).to eq(node.user)
      end

      Backbeat::Client.perform_action(node)
    end
  end

  context 'legacy client' do
    let(:user) {
      FactoryGirl.create(
        :user,
        decision_endpoint: "http://decisions.com/api/v1/workflows/make_decision",
        activity_endpoint: "http://activity.com/api/v1/workflows/perform_activity",
        notification_endpoint: "http://notifications.com/api/v1/workflows/notify_of"
      )
    }
    let(:workflow) { FactoryGirl.create(:workflow, user: user) }
    let(:node) { FactoryGirl.create(:node, workflow: workflow, user: user) }

    context ".make_decision" do
      it "calls the make decision endpoint" do
        node.legacy_type = :decision

        stub = WebMock.stub_request(:post, "http://decisions.com/api/v1/workflows/make_decision").with(
          body: { decision: Backbeat::Client::HashKeyTransformations.camelize_keys(Backbeat::Client::NodeSerializer.call(node)) }.to_json,
          headers: { 'Content-Length'=>/\d*\w/, 'Content-Type'=>'application/json'}
        )
        Backbeat::Client.perform_action(node)

        expect(stub).to have_been_requested
      end

      it "raises an http error unless response is between 200-299" do
        node.legacy_type = :decision

        WebMock.stub_request(:post, "http://decisions.com/api/v1/workflows/make_decision").with(
          body: { decision: Backbeat::Client::HashKeyTransformations.camelize_keys(Backbeat::Client::NodeSerializer.call(node)) }.to_json,
          headers: { 'Content-Length'=>/\d*\w/, 'Content-Type'=>'application/json'}
        ).to_return(status: 404)

        expect { Backbeat::Client.perform_action(node) }.to raise_error(Backbeat::HttpError, "HTTP request for decision failed")
      end
    end

    context ".perform_activity" do
      it "calls the perform activity endpoint" do
        node.legacy_type = :activity

        stub = WebMock.stub_request(:post, "http://activity.com/api/v1/workflows/perform_activity").with(
          :body => { activity: Backbeat::Client::HashKeyTransformations.camelize_keys(Backbeat::Client::NodeSerializer.call(node)) }.to_json,
          :headers => { 'Content-Length'=>/\d*\w/, 'Content-Type'=>'application/json' }
        )

        Backbeat::Client.perform_action(node)

        expect(stub).to have_been_requested
      end

      it "raises an http error unless response is between 200-299" do
        node.legacy_type = :activity

        stub = WebMock.stub_request(:post, "http://activity.com/api/v1/workflows/perform_activity").with(
          :body => { activity: Backbeat::Client::HashKeyTransformations.camelize_keys(Backbeat::Client::NodeSerializer.call(node)) }.to_json,
          :headers => { 'Content-Length'=>/\d*\w/, 'Content-Type'=>'application/json' }
        ).to_return(status: 404)

        expect { Backbeat::Client.perform_action(node) }.to raise_error(Backbeat::HttpError, "HTTP request for activity failed")
      end
    end
  end
end
