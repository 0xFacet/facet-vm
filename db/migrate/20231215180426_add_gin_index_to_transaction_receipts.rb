class AddGinIndexToTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    add_index :transaction_receipts, :logs, using: :gin
  end
end
