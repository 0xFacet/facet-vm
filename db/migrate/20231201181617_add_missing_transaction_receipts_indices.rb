class AddMissingTransactionReceiptsIndices < ActiveRecord::Migration[7.1]
  def change
    add_index :transaction_receipts, :runtime_ms
    add_index :transaction_receipts, :block_number
    add_index :transaction_receipts, [:block_number, :runtime_ms]
  end
end
