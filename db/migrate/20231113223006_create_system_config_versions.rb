class CreateSystemConfigVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :system_config_versions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.jsonb :supported_contracts, default: [], null: false
      t.bigint :start_block_number
      t.string :admin_address
    
      t.index [:block_number, :transaction_index], unique: true
      t.index :transaction_hash, unique: true
    
      t.check_constraint "admin_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
    
      t.timestamps
    end    
  end
end
