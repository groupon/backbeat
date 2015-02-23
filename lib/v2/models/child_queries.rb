module V2
  module ChildQueries
    def all_children_ready?
      !children.where(current_server_status: :pending).exists?
    end

    def not_complete_children
      children.where("current_server_status != 'complete' AND current_server_status != 'deactivated'")
    end

    def all_children_complete?
      !not_complete_children.where("mode != 'fire_and_forget'").exists?
    end

    def print_tree
      puts V2::WorkflowTree.to_string(self)
    end
  end
end
