class InitialMigrations < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.binary :uuid,                  null: false, limit: 16
      t.string :decision_endpoint,     null: false
      t.string :activity_endpoint,     null: false
      t.string :notification_endpoint, null: false
    end
    add_index(:users, :uuid)
    add_index(:users, :id, unique: true)

    create_table :workflows do |t|
      t.binary  :uuid,    null: false,    limit: 16
      t.string  :name,    null: false
      t.string  :decider
      t.text    :subject
      t.integer :user_id, null: false
      t.timestamps
    end
    add_index(:workflows, :uuid)
    add_index(:workflows, :id, unique: true)
    add_foreign_key(:workflows, :users)

    create_table :nodes do |t|
      t.binary   :uuid,                  null: false, limit: 16
      t.string   :mode,                  null: false
      t.string   :current_server_status, null: false
      t.string   :current_client_status, null: false
      t.string   :name,                  null: false
      t.datetime :fires_at
      t.integer  :parent_id
      t.integer  :workflow_id,           null: false
      t.integer  :user_id,               null: false
      t.timestamps
    end
    add_index(:nodes, :uuid)
    add_index(:nodes, :workflow_id)
    add_foreign_key(:nodes, :users)
    add_foreign_key(:nodes, :nodes, column: 'parent_id')

    create_table :client_node_details do |t|
      t.binary  :uuid,     null: false, limit: 16
      t.integer :node_id,  null: false
      t.text    :metadata
      t.text    :data
      t.text    :result
    end
    add_index(:client_node_details, :uuid)
    add_index(:client_node_details, :node_id, unique: true)
    add_foreign_key(:client_node_details, :nodes)

    create_table :status_changes do |t|
      t.binary   :uuid,       null: false, limit: 16
      t.integer  :node_id,    null: false
      t.string   :from_status
      t.string   :to_status
      t.string   :status_type
      t.text     :result
      t.datetime :created_at
    end
    add_index(:status_changes, :uuid)
    add_index(:status_changes, :node_id, unique: false)
    add_foreign_key(:status_changes, :nodes)

    create_table :node_details do |t|
      t.binary  :uuid,              null: false, limit: 16
      t.string  :uuid,              null: false
      t.integer :node_id,           null: false
      t.integer :retries_remaining, null: false
      t.integer :retry_interval,    null: false
      t.string  :legacy_type
      t.text    :valid_next_events
    end
    add_index(:node_details, :uuid)
    add_index(:node_details, :node_id, unique: true)
    add_foreign_key(:node_details, :nodes)
  end
end
