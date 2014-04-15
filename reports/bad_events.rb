require_relative 'report_base'
module Reports
  class BadEvents < ReportBase

    include WorkflowServer::Models

    # Picking April 1st randomly.
    # We will separately verify everything before that date
    START_TIME = Date.parse('2014/04/01').to_time.freeze
    COLLECTOR  = [:bad_decisions, :bad_activities, :bad_flags, :bad_signals, :bad_timers]
    PLUCK_FIELDS  = [:id, :name, :status, :parent_id, :workflow_id].freeze

    def perform
      t0 = Time.now
      errored_workflows = run_report
      unless errored_workflows.empty?
        # Write to the file first since we claim to have already done it in the email.
        id_hash = {}
        errored_workflows.each_pair do |workflow_id, events|
          if workflow_id
            id_hash[workflow_id] = events.map(&:id)
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
      events.group_by(&:workflow_id).select {|workflow_id, events| workflow = Workflow.where(id: workflow_id).only(:id, :status).first; (workflow.nil? || (workflow.status != :complete && workflow.status != :pause))}
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
          (event.workflow && event.workflow.events.where(:status.in => [:error, :timeout]).exists?)
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
      body
    end

    def file
      "/tmp/#{self.class.name.gsub('::', '_').downcase}/#{Date.today}.txt"
    end

  end
end
