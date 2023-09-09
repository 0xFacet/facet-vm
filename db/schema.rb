# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2023_09_08_205257) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "contract_call_receipts", force: :cascade do |t|
    t.string "ethscription_id", null: false
    t.string "caller", null: false
    t.integer "status", null: false
    t.string "function_name"
    t.jsonb "function_args", default: {}, null: false
    t.jsonb "logs", default: [], null: false
    t.datetime "timestamp", null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contract_address"
    t.index ["contract_address"], name: "index_contract_call_receipts_on_contract_address"
    t.index ["ethscription_id"], name: "index_contract_call_receipts_on_ethscription_id", unique: true
    t.check_constraint "caller::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "ethscription_id::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "contract_states", force: :cascade do |t|
    t.string "ethscription_id", null: false
    t.jsonb "state", default: {}, null: false
    t.bigint "block_number", null: false
    t.integer "transaction_index", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contract_address", null: false
    t.index ["block_number", "transaction_index"], name: "index_contract_states_on_block_number_and_transaction_index"
    t.index ["contract_address"], name: "index_contract_states_on_contract_address"
    t.index ["ethscription_id"], name: "index_contract_states_on_ethscription_id"
    t.index ["state"], name: "index_contract_states_on_state", using: :gin
    t.check_constraint "contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "ethscription_id::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "ethscription_id", null: false
    t.string "type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "address", null: false
    t.index ["address"], name: "index_contracts_on_address", unique: true
    t.index ["ethscription_id"], name: "index_contracts_on_ethscription_id"
    t.index ["type"], name: "index_contracts_on_type"
    t.check_constraint "address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "ethscription_id::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "ethscriptions", force: :cascade do |t|
    t.string "ethscription_id", null: false
    t.bigint "block_number", null: false
    t.string "block_blockhash", null: false
    t.integer "transaction_index", null: false
    t.string "creator", null: false
    t.string "initial_owner", null: false
    t.string "current_owner", null: false
    t.datetime "creation_timestamp", null: false
    t.string "previous_owner"
    t.text "content_uri", null: false
    t.string "content_sha", null: false
    t.string "mimetype", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_number", "transaction_index"], name: "index_ethscriptions_on_block_number_and_transaction_index", unique: true
    t.index ["content_sha"], name: "index_ethscriptions_on_content_sha"
    t.index ["ethscription_id"], name: "index_ethscriptions_on_ethscription_id", unique: true
    t.check_constraint "block_blockhash::text ~ '^0x[a-f0-9]{64}$'::text", name: "ethscriptions_block_blockhash_format"
    t.check_constraint "content_sha::text ~ '^[a-f0-9]{64}$'::text", name: "ethscriptions_content_sha_format"
    t.check_constraint "creator::text ~ '^0x[a-f0-9]{40}$'::text", name: "ethscriptions_creator_format"
    t.check_constraint "current_owner::text ~ '^0x[a-f0-9]{40}$'::text", name: "ethscriptions_current_owner_format"
    t.check_constraint "ethscription_id::text ~ '^0x[a-f0-9]{64}$'::text", name: "ethscriptions_ethscription_id_format"
    t.check_constraint "initial_owner::text ~ '^0x[a-f0-9]{40}$'::text", name: "ethscriptions_initial_owner_format"
    t.check_constraint "previous_owner IS NULL OR previous_owner::text ~ '^0x[a-f0-9]{40}$'::text", name: "ethscriptions_previous_owner_format"
  end

  add_foreign_key "contract_call_receipts", "contracts", column: "contract_address", primary_key: "address", on_delete: :cascade
  add_foreign_key "contract_call_receipts", "ethscriptions", primary_key: "ethscription_id", on_delete: :cascade
  add_foreign_key "contract_states", "contracts", column: "contract_address", primary_key: "address", on_delete: :cascade
  add_foreign_key "contract_states", "ethscriptions", primary_key: "ethscription_id", on_delete: :cascade
  add_foreign_key "contracts", "ethscriptions", primary_key: "ethscription_id", on_delete: :cascade
end
