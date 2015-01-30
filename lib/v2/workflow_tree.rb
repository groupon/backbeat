module V2
  class WorkflowTree
    extend Colorize
    def self.to_hash(node)
      {
        id: node.uuid,
        name: node.name,
        status: node.parent ? node.current_server_status : nil,
        children: node.children.map { |child| to_hash(child) }
      }
    end

    def self.to_string(node, depth = 0)
      children = node.children.map do |child|
        to_string(child, depth + 1)
      end.join

      "\n#{node.uuid}#{spacer(depth)}#{node_display(node)}" + children
    end

    def self.spacer(depth)
      cyan("#{('   ' * depth)}\|--")
    end

    def self.node_display(node)
      node_details = "#{node.name}"
      if node.parent
        node_details += " - #{node.current_server_status}"
        node_details = color_details(node.current_server_status.to_sym, node_details)
      end
      node_details
    end

    def self.color_details(server_status, node_details)
      case server_status
      when :started, :sent_to_client, :received_from_client, :processing_children, :retrying
        yellow(node_details)
      when :complete
        green(node_details)
      when :errored
        red(node_details)
      else
        white(node_details)
      end
    end
  end
end
