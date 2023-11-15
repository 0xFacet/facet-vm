class CreateContractArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_artifacts do |t|
      t.string :transaction_hash, null: false
      
      t.string :name, null: false
      t.text :source_code, null: false
      t.string :init_code_hash, null: false
      t.jsonb :references, null: false, default: []
      t.string :pragma_language, null: false
      t.string :pragma_version, null: false
      
      t.index :name
      t.index :init_code_hash, unique: true
      
      t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :ethscriptions, column: :transaction_hash,
        primary_key: :ethscription_id, on_delete: :cascade
      
      t.timestamps
    end
    
    remove_column :contract_calls, :to_contract_type, :string
  end
end
