class AddGasStatsToTransactionReceipts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  
  def change
    add_column :transaction_receipts, :gas_stats, :jsonb, default: {}, null: false
    add_column :transaction_receipts, :facet_gas_used, :float
    
    [:transaction_receipts, :contract_calls, :eth_blocks].each do |table|
      if pg_adapter?
        remove_column table, :runtime_ms
        add_column table, :runtime_ms, :float
      else
        change_column table, :runtime_ms, :float
      end
    end
  end
end
