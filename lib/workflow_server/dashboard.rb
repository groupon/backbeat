require 'httparty'
require 'rufus/scheduler'

AUTH_TOKEN = WorkflowServer::Config.options[:dashboard_auth_token]
DASHBOARD_BASE_URI = WorkflowServer::Config.options[:dashboard_base_uri]

# NOTE For now these are only accurate if there is single user

module Dashboard
  def self.start
    update_dashboard = Rufus::Scheduler.start_new

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Workflow.count
      send_to_dashboard('workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Workflow.where(status: :open).count
      send_to_dashboard('active_workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      workflow_ids = WorkflowServer::Models::Event.where(status: :error).pluck(:workflow_id).uniq
      count = WorkflowServer::Models::Workflow.where(:_id.in => workflow_ids, :status.ne => :pause).count
      send_to_dashboard('errored_workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      workflow_ids = WorkflowServer::Models::Event.where(status: :timeout).pluck(:workflow_id).uniq
      count = WorkflowServer::Models::Workflow.where(:_id.in => workflow_ids, :status.ne => :pause).count
      send_to_dashboard('timed_out_workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Workflow.where(status: :pause).count
      send_to_dashboard('paused_workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      object_ids = WorkflowServer::Models::Event.where(:_type.in => [WorkflowServer::Models::Timer.to_s, WorkflowServer::Models::Signal.to_s]).pluck(:_id)
      duplicate_objects_workflow_ids = group_by_and_having(WorkflowServer::Models::Event.where(:parent_id.in => object_ids).type(WorkflowServer::Models::Decision).selector, 'parent_id', 1).map(&:workflow_id)
      multiple_executing_decisions_workflow_ids = group_by_and_having(WorkflowServer::Models::Event.where(:status.nin => [:open, :complete]).type(WorkflowServer::Models::Decision).selector, 'workflow_id', 1)
      stuck_workflow_ids = WorkflowServer::Models::Decision.where(status: :open, user: current_user).find_all {|decision| decision.workflow.decisions.where(status: :executing).none? }.map(&:workflow_id)

      count = (duplicate_objects_workflow_ids + multiple_executing_decisions_count + stuck_workflow_ids).uniq.count
      send_to_dashboard('inconsistent_workflow_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Activity.where(:status.in => [:executing, :running_sub_activity]).count
      send_to_dashboard('executing_activity_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Activity.where(:status.in => [:retrying, :restarting, :failed]).count
      send_to_dashboard('retrying_activity_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Activity.where(status: :error).count
      send_to_dashboard('errored_activity_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Decision.where(status: :open).count
      send_to_dashboard('open_decision_count', current: count)
    end

    update_dashboard.every '1m' do
      count = WorkflowServer::Models::Timer.where(status: :scheduled).count
      send_to_dashboard('scheduled_timer_count', current: count)
    end

    update_dashboard.every '5m' do
      pause_time = Time.now
      count = WorkflowServer::Models::Timer.where(:fires_at.gt => pause_time).and(:fires_at.lt => (pause_time + 1.day)).count
      send_to_dashboard('timers_firing_within_24_hours_count', current: count)
    end

    update_dashboard.start
    update_dashboard.join
  end

  def self.send_to_dashboard(widget_name, data)
    HTTParty.post(DASHBOARD_BASE_URI + widget_name,
                  :body => {auth_token: AUTH_TOKEN}.merge(data).to_json)
  end

  def self.group_by_and_having(selector, field, count, greater = true)
    result = WorkflowServer::Models::Event.collection.aggregate(
      { '$match' => selector },
      { '$group' => { '_id' =>  "$#{field}", 'count' => { '$sum' => 1 } } },
      { '$match' => { 'count' => { greater ? '$gt' : '$lt' => count } } })

    result.map { |hash| hash['_id'] }
  end
end
