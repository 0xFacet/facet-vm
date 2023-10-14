class AddImplementationVersionToContracts < ActiveRecord::Migration[7.0]
  def change
    add_column :contracts, :implementation_version, :string, null: false
    add_index :contracts, :implementation_version
    
    add_check_constraint :contracts, "implementation_version ~ '^[a-f0-9]{32}$'"
  end
end
