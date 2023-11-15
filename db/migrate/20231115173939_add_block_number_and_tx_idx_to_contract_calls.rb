class AddBlockNumberAndTxIdxToContractCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_calls, :block_number, :bigint, null: false
    add_column :contract_calls, :transaction_index, :bigint, null: false
    
    add_index :contract_calls, [
      :block_number,
      :transaction_index,
      :internal_transaction_index
    ], unique: true
  end
end
