class CreateContractArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_artifacts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :internal_transaction_index, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.string :name, null: false
      t.text :source_code, null: false
      t.string :init_code_hash, null: false
      t.jsonb :references, default: [], null: false
      t.string :pragma_language, null: false
      t.string :pragma_version, null: false
    
      t.index [:block_number, :transaction_index, :internal_transaction_index], unique: true
      t.index [:transaction_hash, :internal_transaction_index], unique: true
      t.index :init_code_hash, unique: true
      t.index :name
    
      t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
    
      # t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end    
  end
end
