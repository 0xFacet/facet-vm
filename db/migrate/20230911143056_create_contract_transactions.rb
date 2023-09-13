class CreateContractTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_transactions do |t|
      t.string :transaction_hash, null: false, index: { unique: true }
      t.string :block_blockhash, null: false
      t.bigint :block_timestamp, null: false
      t.bigint :block_number, null: false
      t.integer :transaction_index, null: false
      
      t.timestamps
    
      t.index [:block_number, :transaction_index], unique: true,
        name: "index_contract_txs_on_block_number_and_tx_index"
        
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'", name: "block_blockhash_format"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'", name: "transaction_hash_format"
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: "ethscription_id", on_delete: :cascade
    end
  end
end
