require_relative 'report_base'

module Reports
  class DailyActivity < ReportBase
    def inconsistent_node_options
      {
        lower_bound: Time.parse('2015/04/01'),
        upper_bound: 12.hours.ago
      }
    end

    def completed_node_options
      upper_bound = Time.now
      {
        lower_bound: upper_bound - 24.hours,
        upper_bound: upper_bound
      }
    end

    def perform
      start_time = Time.now

      # perform calculations
      inconsistent_details = node_and_workflow_details(inconsistent_nodes, { include_ids: true })
      completed_details = node_and_workflow_details(completed_nodes)
      file_name = write_to_file(inconsistent_details[:ids])

      # normalize the data
      report_data = OpenStruct.new({
        inconsistent: { counts: inconsistent_details[:counts], options: inconsistent_node_options, filename: file_name},
        completed: { counts: completed_details[:counts], options: completed_node_options },
        time_elapsed: (Time.now - start_time).to_i
      })

      # generate view
      html_body = report_html_body(report_data)
      send_report(html_body)
    end

    def inconsistent_nodes
      V2::Node
        .where("fires_at > ?", inconsistent_node_options[:lower_bound])
        .where("fires_at < ?", inconsistent_node_options[:upper_bound])
        .select("id, workflow_id, fires_at, current_server_status, current_client_status")
        .where("(current_server_status <> 'complete' OR current_client_status <> 'complete') AND current_server_status <> 'deactivated'")
    end

    def completed_nodes
      V2::Node
        .where("fires_at > ?", completed_node_options[:lower_bound])
        .where("fires_at < ?", completed_node_options[:upper_bound])
        .select("id, workflow_id, fires_at, current_server_status, current_client_status")
        .where("current_server_status = 'complete' AND current_client_status = 'complete'")
    end

    def write_to_file(nodes_by_workflow)
      file_name =  "/tmp/inconsistent_nodes/#{Date.today}.txt"
      FileUtils.mkdir_p(File.dirname(file_name))
      File.open(file_name, 'w') { |file| file.write(nodes_by_workflow.to_json) }
      file_name
    end

    def send_report(body)
      Mail.deliver do
        from    "financial-engineering+backbeat@groupon.com"
        to      "financial-engineering-alerts@groupon.com"
        subject "Backbeat Workflow Report #{Date.today.to_s}"

        html_part do
          content_type 'text/html; charset=UTF-8'
          body body
        end
      end
    end

    def nodes_by_workflow(nodes_arel)
      nodes_by_workflow = Hash.new{|h, k| h[k] = Array.new}
      nodes_arel.reorder("").select("id, workflow_id").find_each{|node| nodes_by_workflow[node.workflow.id] << node.id}
      nodes_by_workflow
    end

    def node_and_workflow_details(nodes_arel, options = {})
      workflow_ids = {}
      nodes_by_workflow = Hash.new{|h, k| h[k] = {workflow_type_count: 0, node_count: 0}}
      node_ids_by_workflow_id = Hash.new{ |h, k| h[k] = Array.new }

      nodes_arel.reorder("").includes(:workflow).select("nodes.id, workflows.name").find_each do |node|
        unless workflow_ids[node.workflow_id]
          workflow_ids[node.workflow_id] = true
          nodes_by_workflow[node.workflow.name][:workflow_type_count] += 1
        end
        node_ids_by_workflow_id[node.workflow.id] << node.id if options[:include_ids]
        nodes_by_workflow[node.workflow.name][:node_count] += 1
      end

      { counts: nodes_by_workflow, ids: node_ids_by_workflow_id }
    end

    def report_html_body(report_model)
      body =  " <!DOCTYPE html>
                <html>
                <body style='min-width:100%'>
                <h2 style='padding-top:14pt;color:#000000;font-size:14pt;font-family:Arial;font-weight:bold;padding-bottom:4pt'>Backbeat Activity Report</h2>"
      if report_model.inconsistent[:counts].empty?
        body += "<p style='direction:ltr;margin:0'>No inconsistent workflows to talk about</p>"
      else
        body += node_and_workflow_table(report_model.inconsistent[:counts], "Workflow Inconsistencies", report_model.inconsistent[:options])
        body += "<p style='direction:ltr;margin:0'>Inconsistent info stored at #{report_model.inconsistent[:filename]}</p>"
      end
      body += node_and_workflow_table(report_model.completed[:counts], "Workflow Activity", report_model.completed[:options])
      body += "<p style='direction:ltr;margin:0'>Report finished in #{report_model.time_elapsed} seconds</p>"
    end

    def node_and_workflow_table(node_and_workflow_count, title, options)
      body  = " <h2 style='padding-top:14pt;color:#000000;font-size:14pt;font-family:Arial;font-weight:bold;padding-bottom:4pt'>#{title}</h2>
                <p style='direction:ltr;margin:0'>Processing window: #{options[:lower_bound].to_s} to #{options[:upper_bound].to_s}</p>
                <table style='width:100%'>
                  <tr>
                    <td style='vertical-align:top;background-color:#b7b7b7;padding:5pt;border:1pt solid #ffffff' bgcolor='#b7b7b7' valign='top'>Workflow Name</td>
                    <td style='vertical-align:top;background-color:#b7b7b7;padding:5pt;border:1pt solid #ffffff' bgcolor='#b7b7b7' valign='top'>Workflow Count</td>
                    <td style='vertical-align:top;background-color:#b7b7b7;padding:5pt;border:1pt solid #ffffff' bgcolor='#b7b7b7' valign='top'>Node Count</td>
                  </tr>
                  "
      node_and_workflow_count.each_pair do |workflow_name, details|
        workflow_count = details[:workflow_type_count]
        node_count = details[:node_count]
        body += "<tr>
                  <td style='vertical-align:top;background-color:#f3f3f3;padding:5pt;border:1pt solid #ffffff' bgcolor='#f3f3f3' valign='top'>#{workflow_name}</td>
                  <td style='vertical-align:top;background-color:#f3f3f3;padding:5pt;border:1pt solid #ffffff' bgcolor='#f3f3f3' valign='top'>#{workflow_count}</td>
                  <td style='vertical-align:top;background-color:#f3f3f3;padding:5pt;border:1pt solid #ffffff' bgcolor='#f3f3f3' valign='top'>#{node_count}</td>
                 </tr>"
      end
      body += "</table>
                </body>
                </html>
                "
    end
  end
end
