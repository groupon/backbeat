require "v2/helpers/colorize"

module V2
  class WorkflowTree
    def self.to_hash(node)
      new(node).to_hash
    end

    def self.to_string(node)
      new(node).to_string
    end

    def initialize(root)
      @root = root
    end

    def each(node = root, &block)
      block.call(node)
      children(node).each do |child|
        each(child, &block)
      end
    end

    def to_hash(node = root)
      {
        id: node.uuid.uuid.to_s,
        name: node.name,
        current_server_status: node.is_a?(Node) ? node.current_server_status : nil,
        current_client_status: node.is_a?(Node) ? node.current_client_status : nil,
        children: children(node).map { |child| to_hash(child) }
      }
    end

    def to_string(node = root, depth = 0)
      child_strings = children(node).map do |child|
        to_string(child, depth + 1)
      end.join

      NodeString.build(node, depth) + child_strings
    end

    private

    attr_reader :root

    def children(node)
      parent_id = node.is_a?(Node) ? node.id : nil
      tree[parent_id] || []
    end

    def tree
      @tree ||= Node.where(
        workflow_id: root.workflow_id
      ).group_by(&:parent_id)
    end

    class NodeString
      include Colorize

      def self.build(node, depth)
        new(node, depth).build
      end

      def initialize(node, depth)
        @node = node
        @depth = depth
      end

      def build
        "\n#{node.uuid.uuid.to_s}#{spacer}#{node_display}"
      end

      private

      attr_reader :node, :depth

      def spacer
        cyan("#{('   ' * depth)}\|--")
      end

      def node_display
        if node.is_a?(Node)
          colorize_details(
            "#{node.name} - "\
            "server: #{node.current_server_status}, "\
            "client: #{node.current_client_status}"
          )
        else
          node.name
        end
      end

      def colorize_details(node_details)
        case node.current_server_status.to_sym
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
end
