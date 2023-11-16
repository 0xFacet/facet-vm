class CreateContracts < ActiveRecord::Migration[7.0]
  def change
    create_table :contracts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.string :current_type, null: false
      t.string :current_init_code_hash, null: false
      t.jsonb :current_state, default: {}, null: false
      t.string :address, null: false
    
      t.index :address, unique: true
      t.index :current_init_code_hash
      t.index :current_type
      t.index :current_state, using: :gin
      t.index :transaction_hash
    
      t.check_constraint "address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "current_init_code_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :ethscription_id, on_delete: :cascade
            
      t.timestamps
    end
  end
end
