class AddRuntimeToContractCallsAndTxs < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_calls, :start_time, :datetime, null: false
    add_column :contract_calls, :end_time, :datetime, null: false
    add_column :contract_calls, :runtime_ms, :integer, null: false
    
    add_column :contract_transaction_receipts, :runtime_ms, :integer, null: false
    
    add_column :contract_transaction_receipts, :call_type, :string, null: false
  end
end
