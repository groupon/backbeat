require_relative 'report_base'
module Reports
  class DailyReport < ReportBase

    def perform
      errored_workflows = run_report
      mail_report(generate_body(errored_workflows)) unless errored_workflows.empty?
    end

    # run is so that it can be invoked as a job by TorqueBox
    def run
      puts "Running Daily Report at #{Time.now}"
      perform
    end

    def run_report
      errored_workflows = Hash.new {|h,k| h[k] = []}
      WorkflowServer::Models::Event.where(:status.in => [:error, :timeout]).each do |event|
        next if event.workflow.paused?
        errored_workflows[event.workflow] << event
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
      end# if WorkflowServer::Config.environment == :production
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
