require_relative 'report_base'

module Reports
  class DailyActivity < ReportBase
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

      def table(title, counts, options)
        ERB.new(
          File.read(File.expand_path('../daily_activity/table.html.erb', __FILE__))
        ).result(binding)
      end
    end
  end
end
