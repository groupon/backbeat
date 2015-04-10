class AddIndexesToWorkflowAndNode < ActiveRecord::Migration
  def change
    add_index(:workflows, [:subject, :name, :user_id, :decider], unique: true)
    add_index(:nodes, :fires_at)
    add_index(:nodes, :current_server_status)
  end
end
