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

require 'sidekiq'
require 'sidekiq/schedulable'
require 'mail'

module Backbeat
  module Workers
    class DailyActivity
      include Sidekiq::Worker
      include Sidekiq::Schedulable

      sidekiq_options retry: false, queue: Config.options[:async_queue]
      sidekiq_schedule Config.options[:schedules][:daily_activity]

      def perform
        start_time = Time.now

        inconsistent_ids = ids_grouped_by_workflow(inconsistent_nodes)
        file_name = write_to_file(inconsistent_ids)

        inconsistent_counts = counts_by_workflow_type(inconsistent_nodes)
        completed_counts = counts_by_workflow_type(completed_nodes)

        report_data = {
          inconsistent: {
            counts: inconsistent_counts,
            options: inconsistent_node_options,
            filename: file_name
          },
          completed: {
            counts: completed_counts,
            options: completed_node_options
          },
          time_elapsed: (Time.now - start_time).to_i
        }

        send_report(report_data)
      end

      private

      def inconsistent_node_options
        {
          lower_bound: Time.parse('2015/04/01'),
          upper_bound: Date.today
        }
      end

      def completed_node_options
        upper_bound = Time.now
        {
          lower_bound: upper_bound - 24.hours,
          upper_bound: upper_bound
        }
      end

      def inconsistent_nodes
        Backbeat::Node
          .where("fires_at > ?", inconsistent_node_options[:lower_bound])
          .where("fires_at < ?", inconsistent_node_options[:upper_bound])
          .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
      end

      def completed_nodes
        Backbeat::Node
          .where("fires_at > ?", completed_node_options[:lower_bound])
          .where("fires_at < ?", completed_node_options[:upper_bound])
          .where("current_server_status = 'complete' AND current_client_status = 'complete'")
      end

      def write_to_file(nodes_by_workflow)
        file_name = "/tmp/inconsistent_nodes/#{Date.today}.txt"
        FileUtils.mkdir_p(File.dirname(file_name))
        File.open(file_name, 'w') { |file| file.write(nodes_by_workflow.to_json) }
        file_name
      end

      def send_report(report)
        Mail.deliver do
          from     Backbeat::Config.options[:alerts][:email_from]
          to       Backbeat::Config.options[:alerts][:email_to]
          subject "Backbeat Workflow Report #{Date.today.to_s}"

          html_part do
            content_type 'text/html; charset=UTF-8'
            body Report.render(report)
          end
        end
      end

      def counts_by_workflow_type(nodes_arel)
        counts_by_type = {}
        results = nodes_arel.joins(:workflow)
          .reorder("")
          .group("workflows.name")
          .select("workflows.name, count(distinct workflow_id) as workflow_type_count, count(*) as node_count")
          .all.each do |result|
          counts_by_type[result.name] = {
            workflow_type_count: result.workflow_type_count,
            node_count: result.node_count
          }
        end
        counts_by_type
      end

      def ids_grouped_by_workflow(nodes_arel)
        nodes_by_workflow = {}
        nodes_arel.select("id,workflow_id")
          .reorder("")
          .group_by(&:workflow_id).each_pair do |workflow_id,nodes|
          nodes_by_workflow[workflow_id] = nodes.map(&:id)
        end
        nodes_by_workflow
      end

      class Report
        attr_reader :report

        def self.render(report)
          new(report).render
        end

        def initialize(report)
          @report = report
        end

        def render
          ERB.new(
            File.read(File.expand_path('../daily_activity/report.html.erb', __FILE__))
          ).result(binding)
        end

        def render_table(title, counts, options)
          ERB.new(
            File.read(File.expand_path('../daily_activity/table.html.erb', __FILE__))
          ).result(binding)
        end
      end
    end
  end
end
