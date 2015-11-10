class RemoveCurrentServerStatusIndex < ActiveRecord::Migration
  disable_ddl_transaction!

  def up
    remove_index :nodes, name: :index_nodes_on_current_server_status, algorithm: :concurrently
  end

  def down
    add_index :nodes, :current_server_status, algorithm: :concurrently
  end
end
