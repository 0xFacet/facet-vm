class CreateInternalTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_transactions do |t|
      t.string :transaction_hash, null: false, index: { unique: true }
      t.integer :internal_transaction_index, null: false
      t.string :from_contract, null: false
      t.string :to_contract_address
      t.string :to_contract_type, null: false
      t.string :created_contract_address, index: { unique: true }
      t.string :interface, null: false
      t.string :function
      t.jsonb :args, null: false, default: {}
      t.string :type, null: false
      t.jsonb :return_value#, null: false, default: {}
      t.jsonb :logs, null: false, default: []
      t.jsonb :error, null: false, default: {}
      t.string :status, null: false

      t.timestamps
      
      t.foreign_key :contract_transactions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      
      t.check_constraint "from_contract ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_contract_address IS NULL OR to_contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
      t.check_constraint "created_contract_address IS NULL OR created_contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
      t.check_constraint "to_contract_address IS NOT NULL OR type != 'create'"
      t.check_constraint "created_contract_address IS NOT NULL OR type = 'create'"
      t.check_constraint "function IS NOT NULL OR type != 'create'"

      t.index :from_contract
      t.index :status
      t.index :type
      t.index :to_contract_address
      t.index [:transaction_hash, :internal_transaction_index], unique: true,
        name: "index_internal_txs_on_contract_tx_id_and_internal_tx_index"
    end
  end
end
