require "v2/workers/async_worker"

module V2
  class Server
    MarkChildrenReady = :mark_children_ready
    ChildrenReady = :children_ready
    ScheduleNextNode = :schedule_next_node
    StartNode = :start_node
    ClientComplete = :client_complete
    ClientProcessing = :client_processing
    ClientError = :client_error
    ClientResolved = :client_resolved
    ProcessChildren = :process_children
    NodeComplete = :node_complete
    RetryNode = :retry_node
    RetryNodeWithBackoff = :retry_node_with_backoff

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

    def self.fire_event(event, node, args = {})
      case event
        when MarkChildrenReady
          Processors.mark_children_ready(node)
        when ChildrenReady
          Processors.children_ready(node)
        when ScheduleNextNode
          Workers::AsyncWorker.async_event(node, :schedule_next_node)
        when StartNode
          Workers::AsyncWorker.schedule_async_event(
            node,
            :start_node,
            node.fires_at
          )
        when ClientProcessing
          Processors.client_processing(node)
        when ClientComplete
          Processors.client_complete(node)
        when ProcessChildren
          Processors.schedule_next_node(node)
        when NodeComplete
          Processors.node_complete(node)
        when ClientError
          Processors.client_error(node, args)
        when RetryNode
          Processors.retry_node(node)
        when RetryNodeWithBackoff
          Workers::AsyncWorker.schedule_async_event(
            node,
            :retry_node,
            Time.now + node.node_detail.retry_interval.minutes
          )
      end
    end
  end
end
