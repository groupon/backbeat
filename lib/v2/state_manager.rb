module V2
  class StateManager

    VALID_STATE_CHANGES = {
      current_client_status: {
        pending: [:ready, :errored],
        ready: [:received, :errored],
        received: [:processing, :complete, :errored],
        processing: [:complete],
        errored: [:received],
        complete: [:complete]
      },
      current_server_status: {
        pending: [:ready, :errored],
        ready: [:started, :errored],
        started: [:sent_to_client, :errored],
        sent_to_client: [:processing_children, :recieved_from_client, :errored],
        processing_children: [:complete],
        errored: [:retrying],
        retrying: [:started, :sent_to_client],
        complete: [:complete]
      }
    }

    def initialize(node)
      @node = node
    end

    def update_status(statuses)
      [:current_client_status, :current_server_status].each do |status_type|
        new_status = statuses[status_type]
        next unless new_status
        validate_status(new_status.to_sym, status_type)
        create_status_change(new_status.to_sym, status_type)
      end
      node.update_attributes!(statuses)
    end

    private

    attr_reader :node

    def create_status_change(new_status, status_type)
      node.status_changes.create!(
        from_status: node_status(status_type),
        to_status: new_status,
        status_type: status_type
      )
    end

    def validate_status(new_status, status_type)
      raise V2::InvalidEventStatusChange.new(
        "Cannot transition #{status_type} to #{new_status} from #{node_status(status_type)}"
      ) unless valid_status_change?(new_status, status_type)
    end

    def valid_status_change?(new_status, status_type)
      new_status && valid_state_changes(status_type).include?(new_status)
    end

    def valid_state_changes(status_type)
      VALID_STATE_CHANGES[status_type][node_status(status_type)]
    end

    def node_status(status_type)
      node.send(status_type).to_sym
    end
  end
end
