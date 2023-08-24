class CreateContracts < ActiveRecord::Migration[7.0]
  def change
    create_table :contracts do |t|
      t.references :contract, null: false, type: :string,
        foreign_key: {
          to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
        }
      
      t.string :type, null: false
      
      t.index :type
      
      t.timestamps
      
      t.check_constraint "contract_id ~ '^0x[a-f0-9]{64}$'"
    end
    
    remove_index :contracts, :contract_id
    add_index :contracts, :contract_id, unique: true
  end
end
