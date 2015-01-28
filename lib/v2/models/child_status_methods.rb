module V2
  module ChildStatusMethods
    def all_children_ready?
      !children.where(current_server_status: :pending).exists?
    end

    def not_complete_children
      children.where("current_server_status != 'complete'")
    end

    def all_children_complete?
      !not_complete_children.where("mode != 'fire_and_forget'").exists?
    end
  end
end
