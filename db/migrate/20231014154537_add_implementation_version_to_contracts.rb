class AddImplementationVersionToContracts < ActiveRecord::Migration[7.0]
  def change
    add_column :contracts, :init_code_hash, :string, null: false
    add_index :contracts, :init_code_hash
    
    add_check_constraint :contracts, "init_code_hash ~ '^[a-f0-9]{64}$'"
  end
end
