module V2
  class Server
    def self.create_workflow(params, user)
      subject = params['subject'].to_json

      Workflow.where(subject: subject).first || Workflow.create!(
        name: params['workflow_type'],
        subject: params['subject'],
        decider: params['decider'],
        user_id: user.id
      )
    end

    def self.add_node(user, parent_node, params)
      node = Node.create!(
        mode: params.fetch(:mode, :blocking).to_sym,
        current_server_status: params[:current_server_status] || :pending,
        current_client_status: params[:current_client_status] || :pending,
        name: params['name'],
        fires_at: params['fires_at'] || Time.now - 1.second,
        parent: parent_node,
        workflow_id: parent_node.workflow_id,
        user_id: user.id
      )
      ClientNodeDetail.create!(
        node: node,
        metadata: params[:options][:client_metadata] || {},
        data: params[:options][:client_data] || {}
      )
      NodeDetail.create!(
        node: node,
        legacy_type: params[:legacy_type],
        retry_interval: params['retry_interval'],
        retries_remaining: params['retry']
      )
      node
    end

    STRATEGIES = {
      Events::ScheduleNextNode => Schedulers::AsyncEvent,
      Events::StartNode => Schedulers::AsyncEventAt,
      Events::RetryNode => Schedulers::AsyncEventInterval
    }

    def self.fire_event(event, node, scheduler = nil)
      scheduler ||= STRATEGIES.fetch(event, Schedulers::PerformEvent)
      scheduler.call(event, node)
    end
  end
end
