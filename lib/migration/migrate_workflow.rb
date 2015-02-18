module Migration
  module MigrateWorkflow
    class WorkflowNotMigratable < StandardError; end

    def self.call(v1_workflow, v2_workflow)
      ActiveRecord::Base.transaction do
        v1_workflow.get_children.each do |signal|
          migrate_signal(signal, v2_workflow)
        end

        v1_workflow.update_attributes!(migrated: true)
      end
    end

    def self.migrate_signal(v1_signal, v2_parent)
      v1_signal.children.each do |decision|
        migrate_node(decision, v2_parent)
      end
    end

    def self.migrate_activity(v1_activity, v2_parent, attrs = {})
      V2::Node.create!(
        uuid: v1_activity.id,
        mode: :blocking,
        current_server_status: server_status(v1_activity),
        current_client_status: client_status(v1_activity),
        name: attrs[:name] || v1_activity.name,
        fires_at: attrs[:fires_at] || Time.now - 1.second,
        parent: v2_parent,
        workflow_id:  v2_parent.workflow_id,
        user_id: v2_parent.user_id,
        client_node_detail: V2::ClientNodeDetail.new(
          metadata: {},
          data: {}
        ),
        node_detail: V2::NodeDetail.new(
          legacy_type: attrs[:legacy_type] || :activity,
          retry_interval: 5,
          retries_remaining: 4
        )
      )
    end

    def self.migrate_node(node, v2_parent)
      raise WorkflowNotMigratable.new("Cannot migrate node #{node.id}") unless can_migrate?(node)

      new_v2_parent = (
        case node
        when WorkflowServer::Models::Decision
          migrate_activity(node, v2_parent, legacy_type: :decision)
        when WorkflowServer::Models::Branch
          migrate_activity(node, v2_parent, legacy_type: :branch)
        when WorkflowServer::Models::Activity
          migrate_activity(node, v2_parent)
        when WorkflowServer::Models::Timer
          node = migrate_activity(node, v2_parent, {
            name: "#{node.name}__timer__",
            fires_at: node.fires_at,
            legacy_type: :timer
          })
          V2::Schedulers::AsyncEventAt.call(V2::Events::StartNode, node)
          node
        when WorkflowServer::Models::WorkflowCompleteFlag
          node = migrate_activity(node, v2_parent, legacy_type: :flag)
          node.workflow.complete!
          node
        when WorkflowServer::Models::ContinueAsNewWorkflowFlag
          migrate_activity(node, v2_parent, legacy_type: :flag)
        when WorkflowServer::Models::Flag
          migrate_activity(node, v2_parent, legacy_type: :flag)
        end
      )

      node.children.each do |child|
        migrate_node(child, new_v2_parent)
      end
    end

    def self.can_migrate?(node)
      if node.is_a?(WorkflowServer::Models::Timer)
        node.status.to_sym == :complete ||
          ([:open, :ready, :scheduled].include?(node.status.to_sym) &&
            (node.fires_at - Time.now) > 1.hour)
      else
        [:open, :ready, :complete].include?(node.status.to_sym)
      end
    end

    def self.client_status(v1_node)
      case v1_node.status
      when :open
        :pending
      when :ready
        :ready
      when :complete
        :complete
      when :scheduled
        :ready
      end
    end

    def self.server_status(v1_node)
      return :deactivated if v1_node.inactive
      case v1_node.status
      when :open
        :pending
      when :ready
        :ready
      when :complete
        :complete
      when :scheduled
        :started
      end
    end
  end
end
