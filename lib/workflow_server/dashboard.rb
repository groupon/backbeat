require 'httparty'

AUTH_TOKEN = '6dy6L8v8942jrbV622dr'
DASHBOARD_BASE_URI = 'http://localhost:3030/widgets/'

# NOTE For now these are only accurate if there is single user

module WorkflowServer
  module Dashboard
    class << self

      def update
        workflow_count
        active_workflow_count
        errored_workflow_count
        timed_out_workflow_count
        paused_workflow_count
        inconsistent_workflow_count
        executing_activity_count
        retrying_activity_count
        errored_activity_count
        open_decision_count
        scheduled_timer_count
        timers_firing_within_24_hours_count
      rescue
        false
      else
        true
      end

      private

      def workflow_count
        count = WorkflowServer::Models::Workflow.count
        send_to_dashboard('workflow_count', current: count)
      end

      def active_workflow_count
        count = WorkflowServer::Models::Workflow.where(status: :open).count
        send_to_dashboard('active_workflow_count', current: count)
      end

      def errored_workflow_count
        count = WorkflowServer::Models::Event.where(status: :error).map(&:workflow_id).uniq.count
        send_to_dashboard('errored_workflow_count', current: count)
      end

      def timed_out_workflow_count
        count = WorkflowServer::Models::Event.where(status: :timeout).map(&:workflow_id).uniq.count
        send_to_dashboard('timed_out_workflow_count', current: count)
      end

      def paused_workflow_count
        count = WorkflowServer::Models::Workflow.where(status: :pause).count
        send_to_dashboard('paused_workflow_count', current: count)
      end

      def inconsistent_workflow_count
        object_ids = WorkflowServer::Models::Event.where(:_type.in => [WorkflowServer::Models::Timer.to_s, WorkflowServer::Models::Signal.to_s]).pluck(:_id)
        duplicate_objects_count = group_by_and_having(WorkflowServer::Models::Event.where(:parent_id.in => object_ids).type(WorkflowServer::Models::Decision).selector, 'parent_id', 1).map(&:workflow_id).uniq.count
        multiple_executing_decisions_count = group_by_and_having(WorkflowServer::Models::Event.where(:status.nin => [:open, :complete]).type(WorkflowServer::Models::Decision).selector, 'workflow_id', 1).count
        send_to_dashboard('inconsistent_workflow_count', current: (duplicate_objects_count + multiple_executing_decisions_count))
      end

      def executing_activity_count
        count = WorkflowServer::Models::Activity.where(:status.in => [:executing, :running_sub_activity]).count
        send_to_dashboard('executing_activity_count', current: count)
      end

      def retrying_activity_count
        count = WorkflowServer::Models::Activity.where(:status.in => [:retrying, :restarting, :failed]).count
        send_to_dashboard('retrying_activity_count', current: count)
      end

      def errored_activity_count
        count = WorkflowServer::Models::Activity.where(status: :error).count
        send_to_dashboard('errored_activity_count', current: count)
      end

      def open_decision_count
        count = WorkflowServer::Models::Decision.where(status: :open).count
        send_to_dashboard('open_decision_count', current: count)
      end

      def scheduled_timer_count
        count = WorkflowServer::Models::Timer.where(status: :scheduled).count
        send_to_dashboard('scheduled_timer_count', current: count)
      end

      def timers_firing_within_24_hours_count
        pause_time = Time.now
        count = WorkflowServer::Models::Timer.where(:fires_at.gt => pause_time).and(:fires_at.lt => (pause_time + 1.day)).count
        send_to_dashboard('timers_firing_within_24_hours_count', current: count)
      end

      def send_to_dashboard(widget_name, data)
        HTTParty.post(DASHBOARD_BASE_URI + widget_name,
                      :body => {auth_token: AUTH_TOKEN}.merge(data).to_json)
      end

      def group_by_and_having(selector, field, count, greater = true)
        result = WorkflowServer::Models::Event.collection.aggregate(
         { '$match' => selector },
         { '$group' => { '_id' =>  "$#{field}", 'count' => { '$sum' => 1 } } },
         { '$match' => { 'count' => { greater ? '$gt' : '$lt' => count } } })

        result.map { |hash| hash['_id'] }
      end

    end
  end
end
