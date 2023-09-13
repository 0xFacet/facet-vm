class UpdateContractTransactionsAssociations < ActiveRecord::Migration[7.0]
  def change
    [:contract_call_receipts, :contract_states, :contracts].each do |table|
      remove_foreign_key table, column: :ethscription_id
      rename_column table, :ethscription_id, :transaction_hash
      add_foreign_key table, :ethscriptions, column: :transaction_hash, primary_key: :ethscription_id, on_delete: :cascade
    end

    rename_table :contract_call_receipts, :contract_transaction_receipts
  end
end
