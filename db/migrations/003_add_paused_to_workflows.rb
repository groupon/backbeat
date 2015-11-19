class AddPausedToWorkflows < ActiveRecord::Migration
  def change
    add_column :workflows, :paused, :boolean
  end
end
