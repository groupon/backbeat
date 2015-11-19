class ChangeStatusChangeIdToBigInt < ActiveRecord::Migration
  def change
    change_column :status_changes, :id, :bigint
  end
end
