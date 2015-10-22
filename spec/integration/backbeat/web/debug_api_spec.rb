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

describe Backbeat::Web::DebugApi, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }

  context "GET /debug/error_workflows" do
    it "returns an empty collection if there are no error nodes" do
      workflow

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(body.size).to eq(0)
    end

    it "returns workflows with nodes in client error state" do
      not_errored_workflow = workflow

      errored_workflow = FactoryGirl.create(
        :workflow_with_node,
        name: :a_unique_name,
        user_id: user.id
      )

      errored_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(errored_workflow.id)
    end

    it "returns workflows scoped to the user" do
      user_workflow = workflow
      user_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      other_user_workflow = FactoryGirl.create(
        :workflow_with_node,
        user: FactoryGirl.create(:user)
      )
      other_user_workflow.children.first.update_attributes(
        current_client_status: :errored,
      )

      response = get("v2/debug/error_workflows")
      body = JSON.parse(response.body)

      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(user_workflow.id)
    end
  end
end
