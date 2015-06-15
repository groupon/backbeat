class InitialMigrations < ActiveRecord::Migration
  def change
    enable_extension('uuid-ossp')

    create_table :users, id: :uuid do |t|
      t.string :decision_endpoint,     null: false
      t.string :activity_endpoint,     null: false
      t.string :notification_endpoint, null: false
    end
    execute("alter table users alter column id set default uuid_generate_v4()")

    create_table :workflows, id: :uuid do |t|
      t.string  :name,     null: false
      t.string  :decider
      t.text    :subject
      t.uuid    :user_id,  null: false
      t.boolean :migrated, default: false
      t.boolean :complete, default: false
      t.timestamps null: false
    end
    execute("alter table workflows alter column id set default uuid_generate_v4()")
    add_foreign_key(:workflows, :users)

    create_table :nodes, id: :uuid do |t|
      t.string   :mode,                  null: false
      t.string   :current_server_status, null: false
      t.string   :current_client_status, null: false
      t.string   :name,                  null: false
      t.datetime :fires_at
      t.uuid     :parent_id
      t.uuid     :workflow_id,           null: false
      t.uuid     :user_id,               null: false
      t.timestamps null: false
    end
    execute("alter table nodes alter column id set default uuid_generate_v4()")
    execute("alter table nodes add column seq serial")
    add_index(:nodes, :seq, unique: true)
    add_index(:nodes, :workflow_id)
    add_index(:nodes, :parent_id)
    add_foreign_key(:nodes, :users)
    add_foreign_key(:nodes, :nodes, column: 'parent_id')

    create_table :client_node_details do |t|
      t.uuid :node_id, null: false
      t.text :metadata
      t.text :data
      t.text :result
    end
    add_index(:client_node_details, :node_id, unique: true)
    add_foreign_key(:client_node_details, :nodes)

    create_table :status_changes do |t|
      t.uuid     :node_id,    null: false
      t.string   :from_status
      t.string   :to_status
      t.string   :status_type
      t.text     :result
      t.datetime :created_at
    end
    add_index(:status_changes, :node_id, unique: false)
    add_foreign_key(:status_changes, :nodes)

    create_table :node_details do |t|
      t.uuid    :node_id,           null: false
      t.integer :retries_remaining, null: false
      t.integer :retry_interval,    null: false
      t.string  :legacy_type
      t.text    :valid_next_events
    end
    add_index(:node_details, :node_id, unique: true)
    add_foreign_key(:node_details, :nodes)
  end
end
