require "migration/workers/migrator"

module Migration

  MIGRATING_TYPES = [:merchant_statement_workflow, :merchant_payment_workflow, :booking_file_workflow]
  ONLY_WITH_ACTIVE_TIMERS = [:merchant_statement_workflow]

  def self.migrate?(type)
    MIGRATING_TYPES.include?(type.to_sym)
  end

  def self.queue_conversion_batch(args)
    types = args[:types] || MIGRATING_TYPES
    limit = args[:limit] || 1000
    WorkflowServer::Models::Workflow.where(
      :workflow_type.in => types,
      :migrated.in => [nil, false]
    ).limit(limit).each do |workflow|
      Migration::Workers::Migrator.perform_async(workflow.id)
    end
  end

  module MigrateWorkflow

    class WorkflowNotMigratable < StandardError; end

    def self.find_or_create_v2_workflow(v1_workflow)
      v2_user_id = V2::User.find_by_id(v1_workflow.user_id).id
      V2::Workflow.where(id: v1_workflow.id).first_or_create!(
        name: v1_workflow.name,
        decider: v1_workflow.decider,
        subject: v1_workflow.subject,
        user_id: v2_user_id,
        complete: v1_workflow.status == :complete
      )
    end

    def self.migrate_signal?(signal)
      if ONLY_WITH_ACTIVE_TIMERS.include?(signal.workflow.workflow_type)
        has_running_timers?(signal)
      else
        true
      end
    end

    def self.call(v1_workflow, v2_workflow)
      ActiveRecord::Base.transaction do
        v1_workflow.get_children.each do |signal|
          if migrate_signal?(signal)
            migrate_signal(signal, v2_workflow)
          end
        end

        v1_workflow.update_attributes!(migrated: true) # for ignoring delayed jobs
        v2_workflow.update_attributes!(migrated: true) # for knowing whether to signal v2 or not
      end
    end

    def self.migrate_signal(v1_signal, v2_parent)
      v1_signal.children.each do |decision|
        migrate_node(decision, v2_parent)
      end
    end

    def self.migrate_activity(v1_activity, v2_parent, attrs = {})
      node = V2::Node.new(
        mode: :blocking,
        current_server_status: server_status(v1_activity),
        current_client_status: client_status(v1_activity),
        name: attrs[:name] || v1_activity.name,
        fires_at: attrs[:fires_at] || Time.now - 1.second,
        parent: v2_parent,
        workflow_id:  v2_parent.workflow_id,
        user_id: v2_parent.user_id,
        client_node_detail: V2::ClientNodeDetail.new(
          metadata: { version: "v2" },
          data: {}
        ),
        node_detail: V2::NodeDetail.new(
          legacy_type: attrs[:legacy_type] || :activity,
          retry_interval: 5,
          retries_remaining: 4
        )
      )
      node.id = v1_activity.id
      node.save!
      node
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
          timer = migrate_activity(node, v2_parent, {
            name: "#{node.name}__timer__",
            fires_at: node.fires_at,
            legacy_type: :timer
          })
          timer.client_node_detail.update_attributes(data: {arguments: [node.name], options: {}})
          V2::Schedulers::AsyncEventAt.call(V2::Events::StartNode, timer) unless timer.current_server_status.to_sym == :complete
          timer.workflow
        when WorkflowServer::Models::WorkflowCompleteFlag
          flag = migrate_activity(node, v2_parent, legacy_type: :flag)
          flag.workflow.complete!
          flag
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
          (node.status.to_sym == :scheduled && (node.fires_at - Time.now) > 1.hour)
      else
        node.status.to_sym == :complete
      end
    end

    def self.client_status(v1_node)
      case v1_node.status
      when :complete
        :complete
      when :scheduled
        :ready
      end
    end

    def self.server_status(v1_node)
      return :deactivated if v1_node.inactive
      case v1_node.status
      when :complete
        :complete
      when :scheduled
        :started
      end
    end

    def self.has_running_timers?(node)
      return true if node.is_a?(WorkflowServer::Models::Timer) && node.status != :complete
      !!node.children.all.to_a.find do |c|
        has_running_timers?(c)
      end
    end
  end
end
