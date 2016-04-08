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

      def perform(options = {})
        start_time = Time.now

        report_range = {
          completed_upper_bound: options[:completed_upper_bound] || start_time,
          completed_lower_bound: options[:completed_lower_bound] || start_time - 24.hours,
          inconsistent_upper_bound: options[:inconsistent_upper_bound] || start_time - 12.hours,
          inconsistent_lower_bound: options[:inconsistent_lower_bound] || start_time - 1.year
        }

        inconsistent_nodes = inconsistent_nodes(report_range)
        inconsistent_counts = counts_by_workflow_type(inconsistent_nodes)
        inconsistent_ids = ids_grouped_by_workflow(inconsistent_nodes)
        file_name = write_to_file(inconsistent_ids)

        completed_nodes = completed_nodes(report_range)
        completed_counts = counts_by_workflow_type(completed_nodes)

        report_data = {
          inconsistent: {
            counts: inconsistent_counts,
            filename: file_name,
            hostname: Config.hostname
          },
          completed: {
            counts: completed_counts,
          },
          time_elapsed: (Time.now - start_time).to_i,
          range: report_range,
          date: start_time.strftime("%m/%d/%Y")
        }

        send_report(report_data)
      end

      private

      def inconsistent_nodes(range)
        Node
          .where("fires_at > ?", range[:inconsistent_lower_bound])
          .where("fires_at < ?", range[:inconsistent_upper_bound])
          .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
      end

      def completed_nodes(range)
        Node
          .where("fires_at > ?", range[:completed_lower_bound])
          .where("fires_at < ?", range[:completed_upper_bound])
          .where("current_server_status = 'complete' AND current_client_status = 'complete'")
      end

      def write_to_file(nodes_by_workflow)
        file_name = "/tmp/inconsistent_nodes/#{Date.today}.json"
        FileUtils.mkdir_p(File.dirname(file_name))
        File.open(file_name, 'w') { |file| file.write(nodes_by_workflow.to_json) }
        file_name
      end

      def counts_by_workflow_type(nodes_arel)
        nodes_arel
          .joins(:workflow)
          .reorder("")
          .group("workflows.name")
          .select("workflows.name, count(distinct workflow_id) as workflow_type_count, count(*) as node_count")
          .reduce({}) do |results, result|
            results[result.name] = {
              workflow_type_count: result.workflow_type_count,
              node_count: result.node_count
            }
            results
          end
      end

      def ids_grouped_by_workflow(nodes_arel)
        nodes_arel
          .select("id, workflow_id")
          .reorder("")
          .reduce(Hash.new { |h, k| h[k] = [] }) do |results, result|
            results[result.workflow_id] << result.id
            results
          end
      end

      def send_report(report)
        email_config = Config.options[:alerts]
        email_from   = email_config[:email_from]
        email_to     = email_config[:email_to]

        if email_from && email_to
          Mail.deliver do
            from     email_from
            to       email_to
            subject "Backbeat Workflow Report #{report[:date]}"

            html_part do
              content_type 'text/html; charset=UTF-8'
              body Report.render(report)
            end
          end
        end
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

        def render_table(title, counts)
          ERB.new(
            File.read(File.expand_path('../daily_activity/table.html.erb', __FILE__))
          ).result(binding)
        end
      end
    end
  end
end
