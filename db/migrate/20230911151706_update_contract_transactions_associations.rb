class UpdateContractTransactionsAssociations < ActiveRecord::Migration[7.0]
  def change
    [:contract_call_receipts, :contract_states, :contracts].each do |table|
      remove_foreign_key table, :ethscriptions, column: :ethscription_id, primary_key: :ethscription_id
      rename_column table, :ethscription_id, :transaction_hash
      add_foreign_key table, :ethscriptions, column: :transaction_hash, primary_key: :ethscription_id, on_delete: :cascade
    end

    rename_table :contract_call_receipts, :contract_transaction_receipts
    
    # TODO ordering should be over block number and tx index
    add_index :contract_transaction_receipts, [:transaction_hash, :created_at],
    name: "index_contract_transaction_receipts_on_tx_hash_and_created_at"
    
    remove_foreign_key "contract_transaction_receipts", "contracts", column: "contract_address", primary_key: "address", on_delete: :cascade
  end
end
