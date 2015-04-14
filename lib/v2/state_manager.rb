module V2
  class StateManager

    VALID_STATE_CHANGES = {
      current_client_status: {
        any: [:errored],
        pending: [:ready],
        ready: [:received],
        received: [:processing, :complete],
        processing: [:complete],
        errored: [:received],
        complete: [:complete]
      },
      current_server_status: {
        any: [:deactivated, :errored],
        deactivated: [:deactivated],
        pending: [:ready],
        ready: [:started],
        started: [:sent_to_client],
        sent_to_client: [:processing_children, :recieved_from_client],
        processing_children: [:complete],
        errored: [:retrying],
        retrying: [:ready],
        complete: [:complete]
      }
    }

    def self.call(node, statuses = {})
      new(node).update_status(statuses)
    end

    def initialize(node)
      @node = node
    end

    def update_status(statuses)
      return if node.is_a?(Workflow)

      [:current_client_status, :current_server_status].each do |status_type|
        new_status = statuses[status_type]
        next unless new_status
        validate_status(new_status.to_sym, status_type)
      end

      create_status_changes(statuses)
      node.update_attributes!(statuses)
    end

    private

    attr_reader :node

    def create_status_changes(new_statuses)
      new_statuses.each do |(status_type, new_status)|
        node.status_changes.create!(
          from_status: node_status(status_type),
          to_status: new_status,
          status_type: status_type
        )
      end
    end

    def validate_status(new_status, status_type)
      current_status = node_status(status_type)
      raise V2::InvalidEventStatusChange.new(
        "Cannot transition #{status_type} from #{current_status} to #{new_status}",
        { current_status: current_status, attempted_status: new_status, status_type: status_type }
      ) unless valid_status_change?(new_status, status_type)
    end

    def valid_status_change?(new_status, status_type)
      new_status && valid_state_changes(status_type).include?(new_status)
    end

    def valid_state_changes(status_type)
      VALID_STATE_CHANGES[status_type][node_status(status_type)] +
        VALID_STATE_CHANGES[status_type][:any]
    end

    def node_status(status_type)
      node.send(status_type).to_sym
    end
  end
end
