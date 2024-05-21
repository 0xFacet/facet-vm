class AddBlockhashIndexToTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    add_index :transaction_receipts, :block_blockhash
  end
end
