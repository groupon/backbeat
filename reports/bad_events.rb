require_relative 'report_base'
module Reports
  class BadEvents < ReportBase

    include WorkflowServer::Models

    # Picking April 1st randomly.
    # We will separately verify everything before that date
    START_TIME = Date.parse('2014/04/01').to_time.freeze
    COLLECTOR  = [:bad_decisions, :bad_activities, :bad_flags, :bad_signals, :bad_timers]
    PLUCK_FIELDS  = [:id, :name, :status, :parent_id, :workflow_id].freeze

    def perform(auto_fix = true)
      t0 = Time.now
      d0 = Date.today
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
        File.open(filename(d0), 'w') { |f| f.write(id_hash.to_json) }

        if auto_fix
          fix(filename(d0)) # run the fixes
          sleep 300; # wait for 5 minutes so that the events have a chance to move along
          perform(false) # run the report again but don't auto fix this time
        else
          mail_report(generate_body(errored_workflows, start_time: t0, start_date: d0))
        end
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
      body = "Report finished running at: #{Time.now}\n"
      body += "#{report_results.count} workflows contain inconsistencies.\n"
      body += "Total time taken #{Time.now - options[:start_time]} seconds\n"
      body += "The workflow ids are stored in #{filename(options[:start_date])}\n"
      body
    end

    def filename(date = Date.today)
      "/tmp/#{self.class.name.gsub('::', '_').downcase}/#{date}.txt"
    end

    def actions
      @actions ||= Hash.new {|h,k| h[k] = [] }
    end

    def fix(report_filename = filename)
      data = JSON.parse(File.read(report_filename))
      data.each_pair do |workflow_id, event_ids|
        workflow = Workflow.find(workflow_id)
        unless workflow
          event_ids.each do |event_id|
            actions[workflow_id] << { event_id => "No action taken. Workflow with id: #{workflow_id} was not found." }
          end
          next
        end
        event_ids.each do |event_id|
          event = Event.find event_id
          next if event.children.where(:_id.in => event_ids, :status.nin => [:open, :complete]).exists? # if there is a stuck child for this event, let's handle the child as it will most likely resolve the parent
          case event
          when WorkflowServer::Models::Signal
            if event.status == :open
              event.enqueue_start
              actions[workflow_id] << { event_id => "Signal: started" }
            end
          when Activity
            case event.status
            when :executing
              event.enqueue_send_to_client
              actions[workflow_id] << { event_id => "Activity: sent_to_client" }
            when :failed
              event.enqueue_start
              actions[workflow_id] << { event_id => "Activity: started" }
            when :retrying
              # 25000 is the largest number of seconds that sidekiq would go between retries with a few minutes of padding added
              if (Time.now - event.updated_at) > (25000 + event.retry_interval)
                event.enqueue_start
                actions[workflow_id] << { event_id => "Activity: retried" }
              end
            end
          when Decision
            case event.status
            when :executing
              event.enqueue_work_on_decisions
              actions[workflow_id] << { event_id => "Decision: work_on_decisions" }
            when :sent_to_client, :deciding
              event.enqueue_send_to_client
              actions[workflow_id] << { event_id => "Decision: sent_to_client" }
            when :open
              WorkflowServer.schedule_next_decision(workflow)
              actions[workflow_id] << { event_id => "Decision: schedule_next_decision" }
            when :retrying
              # 25000 is the largest number of seconds that sidekiq would go between retries with a few minutes of padding added
              if (Time.now - event.updated_at) > (25000 + event.retry_interval)
                event.enqueue_start
                actions[workflow_id] << { event_id => "Activity: retried" }
              end
            end
          when Timer
            case event.status
            when :scheduled
              event.enqueue_start
            end
          end
        end
      end
      actions
    end

  end
end
