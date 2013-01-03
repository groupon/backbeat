class RemoveCurrentServerStatusIndex < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    remove_index(:nodes, name: :index_nodes_on_current_server_status, algorithm: :concurrently)
  end
end
