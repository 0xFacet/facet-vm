class CreateContracts < ActiveRecord::Migration[7.0]
  def change
    create_table :contracts do |t|
      t.references :contract, null: false, type: :string,
        foreign_key: {
          to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
        }
      
      t.string :current_type, null: false
      t.string :current_init_code_hash, null: false
      t.jsonb :current_state, null: false, default: {}
      
      t.index :current_type
      t.index :current_init_code_hash
      
      t.timestamps
      
      t.check_constraint "contract_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "current_init_code_hash ~ '^[a-f0-9]{64}$'"
    end
    
    remove_index :contracts, :contract_id
    add_index :contracts, :contract_id, unique: true
  end
end
