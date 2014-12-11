class InitialMigrations < ActiveRecord::Migration
  def change
    enable_extension 'uuid-ossp'
    enable_extension 'hstore'

    create_table :users, id: false do |t|
      t.uuid :id, primary_key: true, null: false
      t.string :decision_endpoint, null: false
      t.string :activity_endpoint, null: false
      t.string :notification_endpoint, null: false
    end
    add_index(:users, :id, unique: true)

    create_table :workflows, id: false do |t|
      t.uuid :id, unique: true, null: false
      t.string :type, null: false
      t.hstore :subject, null: false
      t.string :decider, null: false
      t.string :initial_signal, null: false
      t.uuid :user_id, null: false
      t.timestamps
    end
    add_index(:workflows, :id, unique: true)
    add_foreign_key(:workflows, :users)

    create_table :nodes, id: false do |t|
      t.uuid :id, unique: true, null: false
      t.string :mode, null: false
      t.string :current_status, null: false
      t.string :name, null: false
      t.datetime :fires_at, null: false
      t.uuid :parent_id, null: false
      t.uuid :workflow_id, null: false
      t.uuid :user_id, null: false
      t.integer :current_delayed_job
      t.timestamps
    end
    add_index(:nodes, :id, unique: true)
    add_foreign_key(:nodes, :workflows)
    add_foreign_key(:nodes, :users)
    add_foreign_key(:nodes, :nodes, column: 'parent_id')

    execute "alter table nodes add column seq serial not null"


    create_table :client_node_details, id: false do |t|
      t.uuid :id, unique: true, null: false
      t.uuid :node_id, null: false
      t.text :metadata
      t.text :data
      t.text :result
    end
    add_index(:client_node_details, :node_id, unique: true)
    add_foreign_key(:client_node_details, :nodes)


    create_table :status_histories do |t|
      t.uuid :id, unique: true, null: false
      t.uuid :node_id, null: false
      t.string :from_status
      t.string :to_status
      t.string :status_type
      t.text :result
      t.datetime :created_at
    end
    add_index(:status_histories, :node_id, unique: false)
    add_foreign_key(:status_histories, :nodes)



    create_table :node_details do |t|
      t.uuid :id, unique: true, null: false
      t.uuid :node_id, null: false
      t.integer  :retry_times_remaining, null: false, default: 3
      t.integer  :retry_interval, null: false,  default: 20
      t.text     :valid_next_events
    end
    add_index(:node_details, :node_id, unique: true)
    add_foreign_key(:node_details, :nodes)

  end
end
