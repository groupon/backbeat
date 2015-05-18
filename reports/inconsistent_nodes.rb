require_relative 'report_base'

module Reports
  class InconsistentNodes < ReportBase

    def default_options
      {
        lower_bound: Time.parse('2015/04/01'),
        upper_bound: 12.hours.ago,
        file_name: file_name(Date.today)
      }
    end

    def perform(options = {})
      start_time = Time.now
      current_options = default_options.merge(options)
      nodes = inconsistent_nodes(current_options)
      #potentially fix inconsistencies here
      nodes_by_workflow = nodes_by_workflow(nodes)
      write_to_file(nodes_by_workflow, current_options[:file_name])
      email_results(nodes_by_workflow, current_options.merge(start_time: start_time))
    end

    def inconsistent_nodes(options)
      V2::Node
        .where("fires_at > ?", options[:lower_bound])
        .where("fires_at < ?", options[:upper_bound])
        .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
    end

    def write_to_file(nodes_by_workflow, file_name)
      FileUtils.mkdir_p(File.dirname(file_name))
      File.open(file_name, 'w') { |file| file.write(nodes_by_workflow.to_json) }
    end

    def email_results(nodes_by_workflow, options)
      count = nodes_by_workflow.keys.count
      if count == 0
        mail_report('No inconsistent workflows to talk about')
      else
        mail_report(cannot_fix_body(count, options))
      end
    end

    def nodes_by_workflow(nodes)
      nodes_by_workflow = Hash.new{|h, k| h[k] = Array.new}
      nodes.each{|node| nodes_by_workflow[node.workflow.id] << node.id}
      nodes_by_workflow
    end

    def file_name(date)
      "/tmp/#{self.class.name.gsub('::', '_').downcase}/#{date}.txt"
    end

    def mail_report(report_body)
      Mail.deliver do
        from    'financial-engineering+backbeat@groupon.com'
        to      'financial-engineering-alerts@groupon.com'
        subject "#{WorkflowServer::Config.environment}: ~BB2~ Inconsistent Workflow Report"
        body    "#{report_body}"
      end
    end

    def cannot_fix_body(workflow_count, options)
      body = "Report finished running at: #{Time.now}\n"
      body += "#{workflow_count} workflows contain inconsistencies.\n"
      body += "Total time taken #{(Time.now - options[:start_time]).to_i} seconds\n"
      body += "The workflow ids are stored in #{options[:file_name]}\n"
      body
    end
  end
end
