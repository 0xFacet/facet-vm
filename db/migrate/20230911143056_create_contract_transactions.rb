class CreateContractTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_transactions do |t|
      t.string :transaction_hash, null: false, index: { unique: true }
      t.string :block_blockhash, null: false
      t.bigint :block_timestamp, null: false
      t.bigint :block_number, null: false
      t.integer :transaction_index, null: false
      t.string :from_address, null: false
      t.string :to_contract_address
      t.string :to_contract_type#, null: false
      t.string :created_contract_address
      t.string :function
      t.jsonb :args, null: false, default: {}
      t.string :type, null: false
      t.jsonb :return_value#, null: false, default: {}
      t.jsonb :logs, null: false, default: []
      t.jsonb :error, null: false, default: {}
      t.string :status, null: false
      
      t.timestamps
      
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: "ethscription_id", on_delete: :cascade
      
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'", name: "transaction_hash_format"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'", name: "block_blockhash_format"
      t.check_constraint "from_address::text ~ '^0x[a-f0-9]{40}$'::text", name: "from_address_format"
      t.check_constraint "to_contract_address IS NULL OR to_contract_address::text ~ '^0x[a-f0-9]{40}$'::text", name: "to_contract_address_format"
      t.check_constraint "created_contract_address IS NULL OR created_contract_address::text ~ '^0x[a-f0-9]{40}$'::text", name: "created_contract_address_format"
      
      # t.check_constraint "to_contract_address IS NOT NULL OR type != 'call'", name: "to_contract_address_or_type"
      # t.check_constraint "created_contract_address IS NOT NULL OR type = 'call'", name: "created_contract_address_or_type"
      # t.check_constraint "function IS NOT NULL OR type != 'call'", name: "function_or_type"
      
      t.index :from_address
      t.index :to_contract_address
      t.index :status
      t.index :type
      t.index [:block_number, :transaction_index], unique: true,
        name: "index_contract_txs_on_block_number_and_tx_index"
    end
  end
end
