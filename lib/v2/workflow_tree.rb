module V2
  class WorkflowTree
    def self.to_hash(node)
      {
        id: node.id,
        name: node.name,
        status: node.parent ? node.current_server_status : nil,
        children: node.children.map { |child| to_hash(child) }
      }
    end

    def self.to_string(node, depth = 0)
      node_display = "#{node.name}"
      node_display += " - #{node.current_server_status}" if node.parent

      children = node.children.map do |child|
        to_string(child, depth + 1)
      end.join

      "\n#{node.id}#{"   " * depth}|--#{node_display}" + children
    end
  end
end
