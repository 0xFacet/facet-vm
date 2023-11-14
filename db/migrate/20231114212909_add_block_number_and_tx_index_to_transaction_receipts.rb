class AddBlockNumberAndTxIndexToTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_transaction_receipts, :block_number, :bigint, null: false
    add_column :contract_transaction_receipts, :transaction_index, :bigint, null: false
    add_column :contract_transaction_receipts, :block_blockhash, :string, null: false
    
    add_index :contract_transaction_receipts, [:block_number, :transaction_index], unique: true
    
    add_check_constraint :contract_transaction_receipts, "block_blockhash ~ '^0x[a-f0-9]{64}$'"
    add_column :eth_blocks, :transaction_count, :bigint
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE eth_blocks
          ADD CONSTRAINT transaction_count_check
          CHECK (processing_state != 'complete' OR transaction_count IS NOT NULL);
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE eth_blocks
          DROP CONSTRAINT transaction_count_check;
        SQL
      end
    end
  end
end
