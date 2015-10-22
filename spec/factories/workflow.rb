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

FactoryGirl.define do
  factory :workflow, class: Backbeat::Workflow do
    name 'WFType'
    subject({'subject_klass'=>'PaymentTerm', 'subject_id'=>'100'})
    decider 'PaymentDecider'

    factory :workflow_with_node do
      after(:create) do |workflow|
        FactoryGirl.create(
          :node,
          parent: workflow,
          workflow_id: workflow.workflow_id,
          user_id: workflow.user_id
        )
      end
    end

    factory :workflow_with_node_running do
      after(:create) do |workflow|
        signal_node = FactoryGirl.create(
          :node,
          parent: workflow,
          workflow_id: workflow.id,
          user_id: workflow.user_id,
          current_server_status: :processing_children,
          current_client_status: :complete
        )

        FactoryGirl.create(
          :node,
          workflow_id: workflow.id,
          user_id: workflow.user_id,
          parent_id: signal_node.id,
          current_server_status: :sent_to_client,
          current_client_status: :received
        )
      end
    end
  end
end


