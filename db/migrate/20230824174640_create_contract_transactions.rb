class CreateContractTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_transactions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.string :block_blockhash, null: false
      t.bigint :block_timestamp, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
    
      t.index [:block_number, :transaction_index], unique: true, name: :index_contract_txs_on_block_number_and_tx_index
      t.index :transaction_hash, unique: true
    
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
    
      # t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end    
  end
end
