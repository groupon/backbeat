module Migration
  module MigrateWorkflow
    def self.call(v1_workflow_id, v2_user_id)
      v1_workflow = WorkflowServer::Models::Workflow.find(v1_workflow_id)

      v2_workflow = V2::Workflow.create(
        uuid: v1_workflow.id,
        name: v1_workflow.name,
        decider: v1_workflow.decider,
        subject: v1_workflow.subject,
        user_id: v2_user_id,
        complete: v1_workflow.status == :complete
      )

      v1_workflow.children.each do |signal|
        migrate_signal(signal, v2_workflow)
      end
    end

    def self.migrate_signal(v1_signal, v2_parent)
      v1_signal.children.each do |decision|
        migrate_node(decision, v2_parent)
      end
    end

    def self.migrate_decision(v1_decision, v2_parent)
      node = V2::Node.create!(
        uuid: v1_decision.id,
        mode: :blocking,
        current_server_status: server_status(v1_decision),
        current_client_status: client_status(v1_decision),
        name: v1_decision.name,
        fires_at: Time.now - 1.second,
        parent: v2_parent,
        workflow_id:  v2_parent.workflow_id,
        user_id: v2_parent.user_id
      )
      V2::ClientNodeDetail.create!(
        node: node,
        metadata: {},
        data: {}
      )
      V2::NodeDetail.create!(
        node: node,
        legacy_type: :decision,
        retry_interval: 5,
        retries_remaining: 4
      )
      node
    end

    def self.migrate_activity(v1_activity, v2_parent)
      node = V2::Node.create!(
        uuid: v1_activity.id,
        mode: :blocking,
        current_server_status: server_status(v1_activity),
        current_client_status: client_status(v1_activity),
        name: v1_activity.name,
        fires_at: Time.now - 1.second,
        parent: v2_parent,
        workflow_id:  v2_parent.workflow_id,
        user_id: v2_parent.user_id
      )
      V2::ClientNodeDetail.create!(
        node: node,
        metadata: {},
        data: {}
      )
      V2::NodeDetail.create!(
        node: node,
        legacy_type: :activity,
        retry_interval: 5,
        retries_remaining: 4
      )
      node
    end

    def self.migrate_node(node, v2_parent)
      new_v2_parent = case node
          when WorkflowServer::Models::Decision
            migrate_decision(node, v2_parent)
          when WorkflowServer::Models::Activity
            migrate_activity(node, v2_parent)
          end

      node.children.each do |child|
        migrate_node(child, new_v2_parent)
      end
    end

    def self.client_status(v1_node)
      case v1_node.status
      when :open
        :pending
      when :complete
        :complete
      end
    end

    def self.server_status(v1_node)
      case v1_node.status
      when :open
        :pending
      when :complete
        :complete
      end
    end
  end
end
