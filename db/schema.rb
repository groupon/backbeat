# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 9) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "uuid-ossp"

  create_table "client_node_details", force: true do |t|
    t.uuid "node_id",  null: false
    t.text "metadata"
    t.text "data"
  end

  add_index "client_node_details", ["node_id"], name: "index_client_node_details_on_node_id", unique: true, using: :btree

  create_table "node_details", force: true do |t|
    t.uuid     "node_id",           null: false
    t.integer  "retries_remaining", null: false
    t.integer  "retry_interval",    null: false
    t.string   "legacy_type"
    t.text     "valid_next_events"
    t.datetime "complete_by"
  end

  add_index "node_details", ["complete_by"], name: "index_node_details_on_complete_by", using: :btree
  add_index "node_details", ["node_id"], name: "index_node_details_on_node_id", unique: true, using: :btree

  create_table "nodes", id: :uuid, default: "uuid_generate_v4()", force: true do |t|
    t.string   "mode",                                                                 null: false
    t.string   "current_server_status",                                                null: false
    t.string   "current_client_status",                                                null: false
    t.string   "name",                                                                 null: false
    t.datetime "fires_at"
    t.uuid     "parent_id"
    t.uuid     "workflow_id",                                                          null: false
    t.uuid     "user_id",                                                              null: false
    t.datetime "created_at",                                                           null: false
    t.datetime "updated_at",                                                           null: false
    t.integer  "seq",                   default: "nextval('nodes_seq_seq'::regclass)", null: false
    t.uuid     "parent_link_id"
  end

  add_index "nodes", ["fires_at"], name: "index_nodes_on_fires_at", using: :btree
  add_index "nodes", ["parent_id"], name: "index_nodes_on_parent_id", using: :btree
  add_index "nodes", ["parent_link_id"], name: "index_nodes_on_parent_link_id", using: :btree
  add_index "nodes", ["seq"], name: "index_nodes_on_seq", unique: true, using: :btree
  add_index "nodes", ["workflow_id"], name: "index_nodes_on_workflow_id", using: :btree

  create_table "status_changes", force: true do |t|
    t.uuid     "node_id",     null: false
    t.string   "from_status"
    t.string   "to_status"
    t.string   "status_type"
    t.text     "response"
    t.datetime "created_at"
  end

  add_index "status_changes", ["node_id"], name: "index_status_changes_on_node_id", using: :btree

  create_table "users", id: :uuid, default: "uuid_generate_v4()", force: true do |t|
    t.string "decision_endpoint"
    t.string "activity_endpoint",     null: false
    t.string "notification_endpoint", null: false
  end

  create_table "workflows", id: :uuid, default: "uuid_generate_v4()", force: true do |t|
    t.string   "name",                       null: false
    t.string   "decider"
    t.text     "subject"
    t.uuid     "user_id",                    null: false
    t.boolean  "migrated",   default: false
    t.boolean  "complete",   default: false
    t.datetime "created_at",                 null: false
    t.datetime "updated_at",                 null: false
    t.boolean  "paused"
  end

  add_index "workflows", ["created_at", "id"], name: "index_workflows_on_created_at_and_id", using: :btree
  add_index "workflows", ["subject", "name", "user_id", "decider"], name: "index_workflows_on_subject_and_name_and_user_id_and_decider", unique: true, using: :btree

end
