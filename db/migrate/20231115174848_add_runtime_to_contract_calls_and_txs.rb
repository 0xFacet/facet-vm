class AddRuntimeToContractCallsAndTxs < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_calls, :start_time, :datetime, null: false
    add_column :contract_calls, :end_time, :datetime, null: false
    add_column :contract_calls, :runtime_ms, :integer, null: false
    
    add_column :contract_transaction_receipts, :runtime_ms, :integer, null: false
    
    add_column :contract_transaction_receipts, :call_type, :string, null: false
    
    add_column :contract_transaction_receipts, :gas_price, :decimal
    add_column :contract_transaction_receipts, :gas_used, :decimal
    add_column :contract_transaction_receipts, :transaction_fee, :decimal
    
    add_column :ethscriptions, :gas_price, :decimal
    add_column :ethscriptions, :gas_used, :decimal
    add_column :ethscriptions, :transaction_fee, :decimal
    
    remove_column :ethscriptions, :content_sha
  end
end
