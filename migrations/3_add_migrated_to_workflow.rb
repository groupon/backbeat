class AddMigratedToWorkflow < ActiveRecord::Migration
  def change
    add_column :workflows, :migrated, :boolean, default: false
  end
end
