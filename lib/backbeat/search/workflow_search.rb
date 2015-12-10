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

module Backbeat
  module Search
    class WorkflowSearch
      def self.filter_for(param, default = nil, &block)
        lambda do |relation, params|
          value = params.fetch(param, default)
          if value
            block.call(relation, params.merge({ param => value }))
          else
            relation
          end
        end
      end

      def initialize(params)
        @params = params
      end

      def result
        apply_filters(
          Workflow.order({ created_at: :desc, id: :desc }),
          NameFilter,
          SubjectFilter,
          CurrentStatusFilter,
          PastStatusFilter,
          StatusStartFilter,
          StatusEndFilter,
          PerPageFilter,
          PageFilter,
          LastIdFilter
        )
      end

      NameFilter = filter_for(:name) do |relation, params|
        relation.where("workflows.name = ?", params[:name])
      end

      SubjectFilter = filter_for(:subject) do |relation, params|
        relation.where("workflows.subject LIKE ?", "%#{params[:subject]}%")
      end

      CurrentStatusFilter = filter_for(:current_status) do |relation, params|
        relation.joins(:nodes).where(
          "nodes.current_server_status = ? OR nodes.current_client_status = ?",
          params[:current_status],
          params[:current_status]
        )
      end

      PastStatusFilter = filter_for(:past_status) do |relation, params|
        relation.joins(:nodes).joins("JOIN status_changes ON status_changes.node_id = nodes.id").where(
          "status_changes.to_status = ?",
          params[:past_status]
        )
      end

      StatusStartFilter = filter_for(:status_start) do |relation, params|
        relation.where("status_changes.created_at >= ?", params[:status_start])
      end

      StatusEndFilter = filter_for(:status_end) do |relation, params|
        relation.where("status_changes.created_at <= ?", params[:status_end])
      end

      PAGE_SIZE = 25

      PerPageFilter = filter_for(:per_page, PAGE_SIZE) do |relation, params|
        limit = params[:per_page].to_i
        relation.limit(limit)
      end

      PageFilter = filter_for(:page, 1) do |relation, params|
        per_page = params.fetch(:per_page, PAGE_SIZE).to_i
        page = params[:page].to_i
        offset = (page - 1) * per_page
        relation.offset(offset)
      end

      LastIdFilter = filter_for(:last_id) do |relation, params|
        last_id = params.fetch(:last_id)
        last_created_at = Workflow.where(id: last_id).pluck(:created_at).first
        relation.where('(created_at, id) < (?, ?)', last_created_at, last_id)
      end

      private

      attr_reader :params

      def apply_filters(base, *filters)
        return [] if params.empty?
        filters.reduce(base) do |relation, filter|
          filter.call(relation, params)
        end.distinct
      end
    end
  end
end
