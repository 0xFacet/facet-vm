class AddLockVersionToContracts < ActiveRecord::Migration[7.1]
  def change
    add_column :contracts, :lock_version, :integer, default: 0, null: false
    add_index :contracts, :lock_version
  end
end
