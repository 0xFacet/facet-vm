class AddFunctionStatsToTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    add_column :transaction_receipts, :function_stats, :jsonb, default: {}, null: false
  end
end
