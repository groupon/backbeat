def actions
  @actions ||= Hash.new {|h,k| h[k] = [] }
end

def handle(workflow, events)
  events.each do |event_id|
    event = Event.find event_id
    next if event.children.where(:_id.in => events, :status.nin => [:open, :complete]).exists? # if there is a stuck child for this event, let's handle the child as it will most likely resolve the parent
    case event
    when WorkflowServer::Models::Signal
      if event.status == :open
        event.enqueue_start
        actions[workflow] << { event_id => "Signal: started" }
      end
    when Activity
      case event.status
      when :executing
        event.enqueue_send_to_client
        actions[workflow] << { event_id => "Activity: sent_to_client" }
      when :failed
        event.enqueue_start
        actions[workflow] << { event_id => "Activity: started" }
      end
    when Decision
      case event.status
      when :executing
        event.enqueue_work_on_decisions
        actions[workflow] << { event_id => "Decision: work_on_decisions" }
      when :sent_to_client, :deciding
        event.enqueue_send_to_client
        actions[workflow] << { event_id => "Decision: sent_to_client" }
      when :open
        WorkflowServer.schedule_next_decision(Workflow.find(workflow))
        actions[workflow] << { event_id => "Decision: schedule_next_decision" }
      end
    when Timer
      case event.status
      when :scheduled
        event.enqueue_start
      end
    end
  end
end

def fix(file)
  data = JSON.parse(File.read(file))
  data.each_pair do |workflow, events|
    handle(workflow, events)
  end
end

ap actions