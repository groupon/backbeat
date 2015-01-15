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
      value = {
        workflow_type: params['workflow_type'],
        subject: params['subject'],
        decider: params['decider'],
        initial_signal: params['sinitial_signal'] || :start,
        user_id: user.id
      }
      if workflow = Workflow.where(subject:  params['subject'].to_json).first
        workflow
      else
        Workflow.create!(value)
      end
    end

    def self.add_node(user, workflow, params, parent_node)
      value = {
        mode: params['mode'].to_sym,
        current_server_status: :pending,
        current_client_status: :pending,
        name: params['name'],
        fires_at: params['fires_at'] || Time.now - 1.second, #not a huge fan of this but would like it to fire imediatly
        parent: parent_node,
        workflow_id: workflow.id,
        user_id: user.id
      }
      node = Node.create!(value)
      ClientNodeDetail.create!(
        node: node,
        metadata: params[:options][:client_metadata] || {},
        data: params[:options][:client_data] || {}
      )
      NodeDetail.create!(
        node: node,
        legacy_type: params['legacy_type'],
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
          Workers::AsyncWorker.async_event(node, :start_node)
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
            node.node_detail.retry_interval
          )
      end
    end
  end
end
