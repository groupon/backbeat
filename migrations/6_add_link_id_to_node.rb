class AddLinkIdToNode < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_column :nodes, :link_id, :uuid
    add_index :nodes, :link_id, algorithm: :concurrently
  end
end
