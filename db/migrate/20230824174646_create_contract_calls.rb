class CreateContractCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_calls, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :internal_transaction_index, null: false
      t.string :from_address, null: false
      t.string :to_contract_address
      t.string :created_contract_address
      t.string :effective_contract_address
      t.string :function
      t.jsonb :args, default: {}, null: false
      t.string :call_type, null: false
      t.jsonb :return_value
      t.jsonb :logs, default: [], null: false
      t.jsonb :error
      t.string :status, null: false
      t.bigint :block_number, null: false
      t.bigint :block_timestamp, null: false
      t.string :block_blockhash, null: false
      t.bigint :transaction_index, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :runtime_ms, null: false
    
      t.index :block_number
      t.index [:block_number, :transaction_index, :internal_transaction_index], unique: true, name: :idx_on_block_number_txi_internal_txi
      t.index :call_type
      t.index :created_contract_address, unique: true
      t.index :effective_contract_address
      t.index :from_address
      t.index :internal_transaction_index
      t.index :status
      t.index :to_contract_address
      t.index [:transaction_hash, :internal_transaction_index], unique: true, name: :idx_on_tx_hash_internal_txi
    
      t.check_constraint "created_contract_address IS NULL OR created_contract_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_contract_address IS NULL OR to_contract_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "effective_contract_address IS NULL OR effective_contract_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      
      t.check_constraint "call_type IN ('call', 'create')"
      t.check_constraint "NOT (call_type = 'create' AND status = 'success' AND created_contract_address IS NULL)"
      t.check_constraint "call_type <> 'call' OR to_contract_address IS NOT NULL"
      t.check_constraint "NOT (status = 'success' AND ((to_contract_address IS NULL) = (created_contract_address IS NULL)))"
      t.check_constraint "(call_type = 'create' AND effective_contract_address = created_contract_address) OR (call_type = 'call' AND effective_contract_address = to_contract_address)"
      
      t.check_constraint "status IN ('success', 'failure')"
      t.check_constraint "(status = 'failure' AND error IS NOT NULL) OR (status = 'success' AND error IS NULL)"
      t.check_constraint "(status = 'failure' AND logs = '[]'::jsonb) OR status = 'success'"
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end    
  end
end
