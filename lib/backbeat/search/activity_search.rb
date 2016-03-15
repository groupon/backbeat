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

require 'backbeat/search/filter'

module Backbeat
  module Search
    class ActivitySearch
      def initialize(params, user_id)
        @params = params
        @user_id = user_id
      end

      def result
        filter.apply_filters(
          params,
          filter.name,
          metadata_filter,
          filter.current_status,
          filter.past_status,
          filter.status_start,
          filter.status_end,
          filter.per_page,
          filter.page,
          filter.last_id
        )
      end

      private

      attr_reader :params, :user_id

      def filter
        @filter ||= Filter.new(Node.where(user_id: user_id).order({ created_at: :desc, id: :desc }))
      end

      def metadata_filter
        filter.filter_for(:metadata) do |relation, params|
          relation.joins("JOIN client_node_details ON client_node_details.node_id = nodes.id")
            .where("client_node_details.metadata LIKE ?", "%#{params[:metadata]}%")
        end
      end
    end
  end
end
