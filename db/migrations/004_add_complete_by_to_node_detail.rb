class AddCompleteByToNodeDetail < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_column :node_details, :complete_by, :datetime
    add_index :node_details, :complete_by, algorithm: :concurrently
  end
end
