module Reports
  class DailyReport < ReportBase
    class << self

      def perform
        mail_report(generate_body(run_report))
      end

      def run_report
        errored_workflows = Hash.new([])
        WorkflowServer::Models::Event.where(:status.in => [:error, :timeout]).each do |event|
          errored_workflows[event.workflow] = errored_workflows[event.workflow] << event
        end
        errored_workflows
      end

      private
      def mail_report(report_body)
        Mail.deliver do
          from    'financial-engineering+backbeat@groupon.com'
          to      'financial-engineering-alerts@groupon.com'
          subject 'Backbeat Workflow Error Report'
          body    "#{report_body}"
        end
      end

      def generate_body(report_results)
        body = "Report was run at: #{Time.now}\n"
        body += "#{report_results.count} workflows contain errors.\n"
        body += "--------------------------------------------------------------------------------"
        report_results.each_pair do |workflow, errored_events|
          body += "\nWorkflow -- ID: #{workflow.id}, Subject: #{workflow.subject}, Error Count: #{errored_events.count}\n"
          errored_events.each do |errored_event|
            body += "\t\t#{errored_event.event_type.capitalize} -- Name: #{errored_event.name}, ID: #{errored_event.id}, Status: #{errored_event.status}\n"
          end
        end
        body
      end

    end
  end
end
