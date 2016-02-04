class AddUserNameAndToken < ActiveRecord::Migration
  def change
    add_column :users, :name, :string
    add_index :users, :name, unique: true

    add_column :users, :auth_token, :string
    add_index :users, :auth_token, unique: true
  end
end
