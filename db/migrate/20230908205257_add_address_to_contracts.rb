class AddAddressToContracts < ActiveRecord::Migration[7.0]
  def up
    add_column :contracts, :address, :string
    Contract.update_all("address = '0x' || RIGHT(contract_id, 40)")
    
    add_column :contract_states, :contract_address, :string
    ContractState.update_all("contract_address = (SELECT address FROM contracts WHERE contracts.contract_id = contract_states.contract_id)")
    
    add_column :contract_call_receipts, :contract_address, :string
    ContractCallReceipt.update_all("contract_address = (SELECT address FROM contracts WHERE contracts.contract_id = contract_call_receipts.contract_id)")
    
    add_check_constraint :contracts,  "address::text ~ '^0x[a-f0-9]{40}$'::text"
    add_check_constraint :contract_states, "contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
    add_check_constraint :contract_call_receipts, "contract_address::text ~ '^0x[a-f0-9]{40}$'::text"
    
    change_column_null :contracts, :address, false
    change_column_null :contract_states, :contract_address, false
    
    add_index :contracts, :address, unique: true
    add_index :contract_states, :contract_address
    add_index :contract_call_receipts, :contract_address
    
    rename_column :contracts, :contract_id, :ethscription_id
    remove_column :contract_states, :contract_id
    remove_column :contract_call_receipts, :contract_id
    
    remove_index :contracts, :ethscription_id
    add_index :contracts, :ethscription_id
    
    remove_index :contract_call_receipts, :ethscription_id
    add_index :contract_call_receipts, :ethscription_id, unique: true
    
    add_foreign_key :contract_states, :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
    add_foreign_key :contract_call_receipts, :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade, uniq: true
  end
  
  def down
    rename_column :contracts, :ethscription_id, :contract_id
    
    remove_foreign_key :contract_states, column: :contract_address
    remove_foreign_key :contract_call_receipts, column: :contract_address
    
    # Restore the `contract_id` columns
    add_column :contract_states, :contract_id, :string
    add_column :contract_call_receipts, :contract_id, :string
    
    # Populate `contract_id` in `contract_states` and `contract_call_receipts` from updated contracts
    ContractState.update_all("contract_id = (SELECT contract_id FROM contracts WHERE contracts.contract_id = contract_states.ethscription_id)")
    ContractCallReceipt.update_all("contract_id = (SELECT contract_id FROM contracts WHERE contracts.contract_id = contract_call_receipts.ethscription_id)")
    
    change_column_null :contract_call_receipts, :contract_id, false
    change_column_null :contract_states, :contract_id, false
    
    # Remove the new columns
    remove_column :contracts, :address
    remove_column :contract_states, :contract_address
    remove_column :contract_call_receipts, :contract_address
    
    add_foreign_key :contract_states, :contracts, column: :contract_address, primary_key: :contract_id, on_delete: :cascade
    add_foreign_key :contract_call_receipts, :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
  end
end
