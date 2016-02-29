class ChangeIntColumnsToBigInt < ActiveRecord::Migration
  def change
    change_column :nodes, :seq, :bigint
    change_column :node_details, :id, :bigint
    change_column :client_node_details, :id, :bigint
  end
end
