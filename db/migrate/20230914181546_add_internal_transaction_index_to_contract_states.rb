class AddInternalTransactionIndexToContractStates < ActiveRecord::Migration[7.0]
  def change
    add_column :contract_states, :internal_transaction_index,
    :integer, null: false
    
    add_index :contract_states, :internal_transaction_index
    add_index :contract_states, [:internal_transaction_index, :transaction_hash], unique: true,
      name: 'index_contract_states_on_internal_tx_index_and_tx_hash'
  end
end
