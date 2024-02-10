class CreateContracts < ActiveRecord::Migration[7.1]
  def change
    create_table :contracts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.string :current_type
      t.string :current_init_code_hash
      t.jsonb :current_state, default: {}, null: false
      t.string :address, null: false
      t.boolean :deployed_successfully, null: false
    
      t.index :deployed_successfully
      t.index [:deployed_successfully, :address], unique: true
      t.index :address, where: "(deployed_successfully = true)", unique: true, name: :idx_on_address_deployed_successfully
      t.index :address, unique: true
      t.index :current_init_code_hash
      t.index :current_type
      t.index :current_state, using: :gin
      t.index :transaction_hash
    
      t.check_constraint "address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "current_init_code_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
    
      # t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
  end
end
