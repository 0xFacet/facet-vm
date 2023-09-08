class AddAddressToContracts < ActiveRecord::Migration[7.0]
  def change
    add_column :contracts, :address, :string
    
    Contract.update_all("address = '0x' || RIGHT(contract_id, 40)")

    change_column_null :contracts, :address, false
    
    add_index :contracts, :address, unique: true
    
    add_check_constraint :contracts,  "address::text ~ '^0x[a-f0-9]{40}$'::text"
    
    # rename_column :contracts, :contract_id, :ethscription_id
  end
end
