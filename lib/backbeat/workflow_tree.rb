require 'backbeat/helpers/colorize'

module Backbeat
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

    def traverse(options = {}, &block)
      _traverse(root, options, &block)
    end

    def to_hash(node = root)
      {
        id: node.id.to_s,
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

    def _traverse(node, options, &block)
      block.call(node) if options.fetch(:root, true)
      children(node).each do |child|
        _traverse(child, options.merge(root: true), &block)
      end
    end

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
        "\n#{node.id.to_s}#{spacer}#{node_display}"
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
        statuses = [node.current_server_status.to_sym, node.current_client_status.to_sym]
        case
        when statuses.include?(:errored)
          red(node_details)
        when statuses.all?{|s| s == :ready}
          white(node_details)
        when statuses.all?{|s| s == :complete}
          green(node_details)
        else
          yellow(node_details)
        end
      end
    end
  end
end
