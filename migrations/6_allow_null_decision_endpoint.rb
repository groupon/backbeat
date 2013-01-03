class AllowNullDecisionEndpoint < ActiveRecord::Migration
  def up
    change_column_null :users, :decision_endpoint, true
  end

  def down
    change_column_null :users, :decision_endpoint, false
  end
end
