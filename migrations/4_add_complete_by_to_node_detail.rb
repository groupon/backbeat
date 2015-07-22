class AddCompleteByToNodeDetail < ActiveRecord::Migration
  def change
    add_column :node_details, :complete_by, :datetime
    add_index :node_details, :complete_by
  end
end
