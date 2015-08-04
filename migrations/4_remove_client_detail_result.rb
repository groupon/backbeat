class RemoveClientDetailResult < ActiveRecord::Migration
  def up
    remove_column :client_node_details, :result
  end

  def down
    add_column :client_node_details, :result, :text
  end
end
