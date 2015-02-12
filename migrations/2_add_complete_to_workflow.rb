class AddCompleteToWorkflow < ActiveRecord::Migration
  def change
    add_column :workflows, :complete, :boolean, default: false
  end
end
