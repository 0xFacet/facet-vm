class CreateContractCalls < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_calls, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :internal_transaction_index, null: false
      t.string :from_address, null: false
      t.string :to_contract_address
      t.string :to_contract_type
      t.string :created_contract_address, index: { unique: true }
      t.string :effective_contract_address, null: true
      t.string :function
      t.jsonb :args, default: {}, null: false
      t.integer :call_type, null: false
      t.jsonb :return_value
      t.jsonb :logs, default: [], null: false
      t.string :error
      t.integer :status, null: false
      
      t.timestamps
    
      t.index [:transaction_hash, :internal_transaction_index], unique: true, name: "index_contract_calls_on_contract_tx_id_and_internal_tx_index"
      t.index :effective_contract_address
      t.index :internal_transaction_index
      t.index :from_address
      t.index :to_contract_address
      t.index :call_type
      t.index :status
      
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :ethscription_id, on_delete: :cascade
      
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'", name: "transaction_hash_format"
      t.check_constraint "created_contract_address IS NULL OR created_contract_address ~ '^0x[a-f0-9]{40}$'", name: "created_contract_address_format"
      t.check_constraint "to_contract_address IS NULL OR to_contract_address ~ '^0x[a-f0-9]{40}$'", name: "to_contract_address_format"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'", name: "from_address_format"
      t.check_constraint "(call_type <> 2 OR error IS NOT NULL) OR (created_contract_address IS NOT NULL)", name: "call_type_2_error_or_created_contract_address"
      t.check_constraint "(call_type = 2 AND error IS NULL) OR (created_contract_address IS NULL)", name: "call_type_2_error_or_created_contract_address2"
      t.check_constraint "(status = 0 AND error IS NOT NULL) OR (status != 0 AND error IS NULL)", name: "status_0_error_or_status_not_0_error"
      t.check_constraint "(status = 0 AND logs = '[]'::jsonb) OR (status != 0)", name: "status_0_logs_empty_or_status_not_0"
      t.check_constraint "(call_type = 2 AND effective_contract_address = created_contract_address) OR (call_type <> 2 AND effective_contract_address = to_contract_address)", name: "effective_contract_address_correct"
    end
  end
end
