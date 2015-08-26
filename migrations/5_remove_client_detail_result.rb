class RemoveClientDetailResult < ActiveRecord::Migration
  def up
    remove_column :client_node_details, :result
    rename_column :status_changes, :result, :response
  end

  def down
    add_column :client_node_details, :result, :text
    rename_column :status_changes, :response, :result
  end
end
