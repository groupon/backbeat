class AddLinkIdToNode < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_column :node, :link_id, :uuid
    add_index :node, :link_id, algorithm: :concurrently
  end
end
