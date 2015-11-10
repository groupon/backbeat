class AddParentLinkIdToNode < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_column :nodes, :parent_link_id, :uuid
    add_index :nodes, :parent_link_id, algorithm: :concurrently
  end
end
