class UpdateContractTransactionsAssociations < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :contract_call_receipts, :ethscriptions,
      primary_key: "ethscription_id", on_delete: :cascade
     
    remove_foreign_key :contract_states, :ethscriptions,
      primary_key: "ethscription_id", on_delete: :cascade
      
    remove_foreign_key :contracts, :ethscriptions,
      primary_key: "ethscription_id", on_delete: :cascade
    
    rename_column :contract_call_receipts, :ethscription_id, :transaction_hash
    rename_column :contract_states, :ethscription_id, :transaction_hash
    rename_column :contracts, :ethscription_id, :transaction_hash
    
    add_foreign_key "contract_call_receipts", "ethscriptions", column: "transaction_hash", primary_key: "ethscription_id", on_delete: :cascade
    
    add_foreign_key "contract_states", "ethscriptions", column: "transaction_hash", primary_key: "ethscription_id", on_delete: :cascade
    
    add_foreign_key "contracts", "ethscriptions", column: "transaction_hash", primary_key: "ethscription_id", on_delete: :cascade
    
    # add_foreign_key :contract_call_receipts, :contract_transactions, column: :transaction_hash, 
    #   primary_key: :transaction_hash, on_delete: :cascade
    # add_foreign_key :contract_states, :contract_transactions, column: :transaction_hash,
    #   primary_key: :transaction_hash, on_delete: :cascade
      
    # add_foreign_key :contracts, :contract_transactions, column: :transaction_hash,
    #   primary_key: :transaction_hash, on_delete: :cascade
    # add_foreign_key :contracts, :internal_transactions, column: :address,
    #   primary_key: :created_contract_address, on_delete: :cascade
    # add_foreign_key :contracts, :contract_transactions, column: :address,
    #   primary_key: :created_contract_address, on_delete: :cascade

    rename_table :contract_call_receipts, :contract_transaction_receipts
  end
end
