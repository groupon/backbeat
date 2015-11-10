class AddWorkflowsCreatedAtIndex < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_index :workflows, [:created_at, :id], algorithm: :concurrently
  end
end
