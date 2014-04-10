require_relative 'report_base'
module Reports
  class BadEvents < ReportBase

    include WorkflowServer::Models

    # Picking October 1st randomly.
    # We will separately verify everything before that date
    START_TIME = Date.parse('2014/03/01').to_time.freeze
    COLLECTOR  = [:bad_decisions, :bad_activities, :bad_flags, :bad_signals, :bad_timers]
    PLUCK_FIELDS  = [:id, :name, :status, :parent_id, :workflow_id].freeze

    def perform
      t0 = Time.now
      errored_workflows = run_report
      unless errored_workflows.empty?
        # Write to the file first since we claim to have already done it in the email.
        id_hash = {}
        errored_workflows.each_pair do |workflow, events|
          if workflow
            id_hash[workflow.id] = events.map(&:id)
          else
            id_hash[nil] = events.map(&:id)
          end
        end
        File.open(file, 'w') { |f| f.write(id_hash.to_json) }

        mail_report(generate_body(errored_workflows, time: Time.now - t0))
      else
        mail_report('No inconsistent workflows to talk about')
      end
    end

    def run_report
      events = []
      COLLECTOR.each { |collector| events << ignore_errors(send(collector)) }
      events.flatten!
      events.compact!
      events.group_by(&:workflow).select {|workflow, events| (workflow.nil? || (workflow.status != :complete && workflow.status != :pause))}
    end

    private

    # This method takes unusually long on backbeat prod. Breaking it into individual methods below
    def bad_events
      Event.not_in(_type: [Timer, Workflow]).where(:status.ne => :complete, updated_at: (START_TIME..1.day.ago)).only(*PLUCK_FIELDS)
    end

    {
      decisions:  WorkflowServer::Models::Decision,
      activities: WorkflowServer::Models::Activity,
      flags:      WorkflowServer::Models::Flag,
      signals:    WorkflowServer::Models::Signal
    }.each_pair do |method_name, klass|
      define_method("bad_#{method_name}") do
        klass.where(:status.ne => :complete, updated_at: (START_TIME..1.day.ago)).only(*PLUCK_FIELDS)
      end
    end

    def bad_timers
      Timer.where(:status.ne => :complete, fires_at: (START_TIME..1.day.ago), :updated_at.lt => 1.day.ago).only(*PLUCK_FIELDS)
    end

    def ignore_errors(query)
      # ignore workflows that have at least one event in error or timeout state or
      # the workflow is paused or
      # the event has a blocking timer underneath that will fire in the future
      query.delete_if do |event|
        event.status == :error || event.status == :timeout ||
          (event.status == :resolved && event.parent.status == :complete) ||
          (event.workflow && event.workflow.events.where(:status.in => [:error, :timeout]).exists?) ||
          event.children.type(Timer).where(status: :scheduled, mode: :blocking, :fires_at.gt => Time.now).exists?
      end
    end

    def mail_report(report_body)
      Mail.deliver do
        from    'financial-engineering+backbeat@groupon.com'
        to      'financial-engineering-alerts@groupon.com'
        subject "#{WorkflowServer::Config.environment}: Backbeat Inconsistent Workflow Report"
        body    "#{report_body}"
      end
    end

    def generate_body(report_results, options = {})
      body = "Report was run at: #{Time.now}\n"
      body += "#{report_results.count} workflows contain inconsistencies.\n"
      body += "Total time taken #{options[:time]} seconds\n" if options[:time]
      body += "The workflow ids are stored in #{file}\n"
      body += "--------------------------------------------------------------------------------"
      report_results.each_pair do |workflow, bad_events|
        if workflow
          body += "\nWorkflow -- ID: #{workflow.id}, Subject: #{workflow.subject}, Inconsistent Event Count: #{bad_events.count}\n"
        else
          body += "\nWorkflow Missing, Inconsistent Event Count: #{bad_events.count}\n"
        end
        bad_events.each do |errored_event|
          body += "\t\t#{errored_event.event_type.capitalize} -- Name: #{errored_event.name}, ID: #{errored_event.id}, Status: #{errored_event.status}\n"
        end
      end
      body
    end

    def file
      "/tmp/#{self.class.name.gsub('::', '_').downcase}/#{Date.today}.txt"
    end

  end
end
