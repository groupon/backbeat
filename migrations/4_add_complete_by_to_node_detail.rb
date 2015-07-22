class AddCompleteByToNodeDetail < ActiveRecord::Migration
  def change
    add_column :node_details, :complete_by, :datetime
  end
end
