require "v2/helpers/colorize"

module V2
  class WorkflowTree
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

      NodeString.build(node, depth) + children
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
        "\n#{node.uuid}#{spacer}#{node_display}"
      end

      private

      attr_reader :node, :depth

      def spacer
        cyan("#{('   ' * depth)}\|--")
      end

      def node_display
        if node.parent
          colorize_details("#{node.name} - #{node.current_server_status}")
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
