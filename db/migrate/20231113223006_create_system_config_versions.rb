class CreateSystemConfigVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :system_config_versions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.jsonb :supported_contracts, default: [], null: false
      t.bigint :start_block_number#, null: false
    
      t.index [:block_number, :transaction_index], unique: true
      t.index :transaction_hash, unique: true
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
    
      t.timestamps
    end    
  end
end
