require_relative 'report_base'
module Reports
  class BadEvents < ReportBase

    include WorkflowServer::Models

    BAD_EVENT_FINDERS = [ Decision, Activity, Flag, WorkflowServer::Models::Signal ].map do |klass|
      Proc.new do |latest_known_good_time, latest_possible_bad_time|
        klass.where(:status.ne => :complete, updated_at: (latest_known_good_time..latest_possible_bad_time)).only(*PLUCK_FIELDS)
      end
    end

    BAD_EVENT_FINDERS << Proc.new do |latest_known_good_time, latest_possible_bad_time|
      Timer.where(:status.ne => :complete, fires_at: (latest_known_good_time..latest_possible_bad_time), :updated_at.lt => latest_possible_bad_time).only(*PLUCK_FIELDS)
    end

    PLUCK_FIELDS  = [:id, :name, :status, :parent_id, :workflow_id]

    def default_options
      {supress_auto_fix: false,
       latest_known_good_time: Time.parse('2014/04/27'), # last known good date. We will separately verify everything after that date
       latest_possible_bad_time: 1.day.ago, # Nothing modified since this time will be considered bad
       filename: filename(Date.today),
       start_time: Time.now,
       recurse_level: -1,
       bad_event_finders: BAD_EVENT_FINDERS,
       time_to_sleep_after_fixing: 1800
      }
    end

    def perform(options = {})
      options = default_options.merge(options)
      options[:recurse_level] += 1

      errored_workflows = run_report(options[:latest_known_good_time], options[:latest_possible_bad_time], options[:bad_event_finders])
      errored_workflow_ids = errored_workflows.keys

      unless errored_workflows.empty?
        # Write to the file first since we claim to have already done it in the email.
        id_hash = {}
        errored_workflows.each_pair do |workflow_id, events|
          id_hash[workflow_id] = events.map(&:id)
        end

        File.open(options[:filename], 'w') { |f| f.write(id_hash.to_json) }

        if options[:suppress_auto_fix]
          mail_report(generate_body(errored_workflows, start_time: options[:start_time], filename: options[:filename]))
        else
          actions_taken = fix(options[:filename]) # run the fixes

          File.open("#{options[:filename]}.fix_results", "wb") { |f| f.write actions_taken.to_json }

          sleep(options[:time_to_sleep_after_fixing]); # wait so that the events have a chance to move along

          perform(options.merge(filename: "#{options[:filename]}.post_fix", suppress_auto_fix: true, bad_event_finders: scope_finders_by_workflow_ids(options[:bad_event_finders],errored_workflow_ids) )) # run the report again but don't auto fix this time
        end
      else
        if options[:recurse_level] > 0
          mail_report("No inconsistent workflows after #{options[:recurse_level]} additional run(s)")
        else
          mail_report('No inconsistent workflows to talk about')
        end
      end
    end

    def run_report(latest_known_good_time, latest_possible_bad_time, bad_event_finders)
      events = []
      bad_event_finders.each { |collector| events << ignore_errors(collector.call(latest_known_good_time, latest_possible_bad_time)) }
      events.flatten!
      events.compact!
      events.group_by(&:workflow_id).select {|workflow_id, events| workflow = Workflow.where(id: workflow_id).only(:id, :status).first; (workflow.nil? || (workflow.status != :complete && workflow.status != :pause))}
    end

    def scope_finders_by_workflow_ids( finders, workflow_ids )
      finders.map do |collector|
        Proc.new { |latest_known_good_time, latest_possible_bad_time| collector.call(latest_known_good_time, latest_possible_bad_time).where(:workflow_id.in => workflow_ids) }
      end
    end

    def ignore_errors(query)
      # ignore workflows that have at least one event in error or timeout state or
      # the workflow is paused or
      # the event has a blocking timer underneath that will fire in the future
      query.delete_if do |event|
        event.status == :error || event.status == :timeout ||
          (event.status == :resolved && event.parent.try(:status) == :complete) ||
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
      body += "The workflow ids are stored in #{options[:filename]}\n"
      body
    end

    def filename(date)
      "/tmp/#{self.class.name.gsub('::', '_').downcase}/#{date}.txt"
    end

    def actions
      @actions ||= {}
    end

    def fix(report_filename)
      data = JSON.parse(File.read(report_filename))
      data.each_pair do |workflow_id, event_ids|
        workflow = Workflow.find(workflow_id)

        unless workflow
          event_ids.each do |event_id|
            actions[workflow_id] = { event_id => "No action taken. Workflow with id: #{workflow_id} was not found." }
          end
          next
        end

        # we want to look at events in sequence order (create order), which is what this gives
        events = workflow.events.where(:id.in => event_ids)

        events.each do |event|
          event.transaction do
            event_id = event.id

            next if event.children.where(:_id.in => event_ids).exists? # if there is a stuck child for this event, let's handle the child as it will most likely resolve the parent

            case event
            when WorkflowServer::Models::Signal
              if event.status == :open
                event.start
                actions[workflow_id] = { event_id => "Signal: started" }
              end
            when Branch
              case event.status
              when :open
                event.start
                actions[workflow_id] = { event_id => "Branch: started" }
              when :executing
                if( event.children.count > 0 )
                  event.update_status!(:complete)
                  event.parent.child_completed(event.id)
                  actions[workflow_id] = { event_id => "Branch: marked completed, notified parent" }
                else
                  event.enqueue_send_to_client
                  actions[workflow_id] = { event_id => "Branch: sent_to_client" }
                end
              when :failed
                event.cleanup
                event.start
                actions[workflow_id] = { event_id => "Branch: started" }
              when :retrying
                # 25000 is the largest number of seconds that sidekiq would go between retries with a few minutes of padding added
                if (Time.now - event.updated_at) > (25000 + event.retry_interval)
                  event.cleanup
                  event.start
                  actions[workflow_id] = { event_id => "Branch: retried" }
                end
              end
            when Activity
              case event.status
              when :executing
                event.enqueue_send_to_client
                actions[workflow_id] = { event_id => "Activity: sent_to_client" }
              when :failed
                event.cleanup
                event.start
                actions[workflow_id] = { event_id => "Activity: started" }
              when :retrying
                # 25000 is the largest number of seconds that sidekiq would go between retries with a few minutes of padding added
                if (Time.now - event.updated_at) > (25000 + event.retry_interval)
                  event.cleanup
                  event.start
                  actions[workflow_id] = { event_id => "Activity: retried" }
                end
              end
            when Decision
              case event.status
              when :executing
                event.send(:work_on_decisions)
                actions[workflow_id] = { event_id => "Decision: work_on_decisions" }
              when :sent_to_client, :deciding
                event.enqueue_send_to_client
                actions[workflow_id] = { event_id => "Decision: sent_to_client" }
              when :open
                if event.parent.is_a?(Branch)
                  event.start
                  actions[workflow_id] = { event_id => "Decision: start" }
                else
                  WorkflowServer.schedule_next_decision(workflow)
                  actions[workflow_id] = { event_id => "Decision: schedule_next_decision" }
                end
              when :retrying
                # 25000 is the largest number of seconds that sidekiq would go between retries with a few minutes of padding added
                if (Time.now - event.updated_at) > (25000 + event.retry_interval)
                  event.start
                  actions[workflow_id] = { event_id => "Activity: retried" }
                end
              end
            when Timer
              case event.status
              when :scheduled
                event.start
                actions[workflow_id] = { event_id => "Timer: start" }
              end
            end
          end

          break if actions[workflow_id]

        end
      end

      actions
    end

  end
end
