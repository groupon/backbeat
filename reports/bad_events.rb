require_relative 'report_base'
module Reports
  class BadEvents < ReportBase

    include WorkflowServer::Models

    # Picking October 1st randomly.
    # we need a separate thing to go in the past before this date
    START_TIME = Date.parse("01/10/2013").to_time.freeze
    COLLECTOR  = [:bad_decisions, :bad_activities, :bad_flags, :bad_signals, :bad_timers]
    PLUCK_FIELDS  = [:id, :name, :status, :parent_id, :workflow_id].freeze

    def perform
      t0 = Time.now
      errored_workflows = run_report
      unless errored_workflows.empty?
        mail_report(generate_body(errored_workflows, time: Time.now - t0))
        File.open(file, "w") { |f| f.write(errored_workflows.keys.map(&:id).to_json) }
      else
        mail_report("No inconsistent workflows to talk about")
      end
    end

    def run_report
      events = []
      COLLECTOR.each { |collector| events << ignore_errors(send(collector)) }
      events.flatten!
      events.compact!
      events.group_by(&:workflow)
    end

    private

    # This method takes unusually long on backbeat prod. Breaking it into individual methods below
    def bad_events
      Event.not_in(_type: [Timer, Workflow]).where(:status.ne => :complete, updated_at: (START_TIME..12.hours.ago)).only(*PLUCK_FIELDS)
    end

    {
      decisions:  WorkflowServer::Models::Decision,
      activities: WorkflowServer::Models::Activity,
      flags:      WorkflowServer::Models::Flag,
      signals:    WorkflowServer::Models::Signal
    }.each_pair do |method_name, klass|
      define_method("bad_#{method_name}") do
        klass.where(:status.ne => :complete, updated_at: (START_TIME..12.hours.ago)).only(*PLUCK_FIELDS)
      end
    end

    def bad_timers
      Timer.where( { "$or" => [ {status: :open, updated_at: (START_TIME..12.hours.ago)}, 
                   { :status.ne => :complete, :fires_at.lt => Time.now} ] }).only(*PLUCK_FIELDS)
    end

    def ignore_errors(query)
      # ignore workflows that have at least one event in error or timeout state or the workflow is paused
      query.find_all do |event|
        event.status != :error && event.status != :timeout &&
        !event.workflow.paused? &&
        event.workflow.events.where(:status.in => [:error, :timeout]).none? &&
        event.children.type(Timer).where(status: :scheduled, mode: :blocking, :fires_at.gt => Time.now).none?
      end
    end

    def mail_report(report_body)
      Mail.deliver do
        from    'financial-engineering+backbeat@groupon.com'
        to      'financial-engineering-alerts@groupon.com'
        subject 'Backbeat Inconsistent Workflow Report'
        body    "#{report_body}"
      end
    end

    def generate_body(report_results, options = {})
      body = "Report was run at: #{Time.now}\n"
      body += "#{report_results.count} workflows contain errors.\n"
      body += "Total time taken #{options[:time]} seconds\n" if options[:time]
      body += "The workflow ids are stored in #{file}\n"
      body += "--------------------------------------------------------------------------------"
      report_results.each_pair do |workflow, bad_events|
        body += "\nWorkflow -- ID: #{workflow.id}, Subject: #{workflow.subject}, Inconsistent Event Count: #{bad_events.count}\n"
        bad_events.each do |errored_event|
          body += "\t\t#{errored_event.event_type.capitalize} -- Name: #{errored_event.name}, ID: #{errored_event.id}, Status: #{errored_event.status}\n"
        end
      end
      body
    end

    def file
      "/tmp/#{self.class.name.gsub('::', '_').downcase}.txt"
    end

  end
end
