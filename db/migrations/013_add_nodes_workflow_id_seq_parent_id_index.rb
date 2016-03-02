class AddNodesWorkflowIdSeqParentIdIndex < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_index :nodes, [:workflow_id, :seq, :parent_id], algorithm: :concurrently
  end
end
