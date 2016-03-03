class RemoveForeignKeys < ActiveRecord::Migration
  def up
    remove_foreign_key(:client_node_details, :nodes)
    remove_foreign_key(:node_details, :nodes)
    remove_foreign_key(:status_changes, :nodes)
    remove_foreign_key(:nodes, name: 'nodes_parent_id_fk')
  end

  def down
    add_foreign_key(:client_node_details, :nodes)
    add_foreign_key(:node_details, :nodes)
    add_foreign_key(:status_changes, :nodes)
    add_foreign_key(:nodes, :nodes, column: 'parent_id')
  end
end
