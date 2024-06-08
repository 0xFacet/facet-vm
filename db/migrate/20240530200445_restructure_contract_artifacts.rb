class RestructureContractArtifacts < ActiveRecord::Migration[7.1]
  def up
    create_table :contract_artifacts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      
      t.string :name, null: false
      t.column :ast, :jsonb, default: {}, null: false
      t.string :init_code_hash, null: false
      t.text :execution_source_code, null: false
      t.column :abi, :jsonb, default: [], null: false
      
      t.text :legacy_source_code
    
      t.index :init_code_hash, unique: true
      t.index :name
      t.index [:block_number, :transaction_index]
      t.index :transaction_hash
    
      if pg_adapter?
        t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
      end
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
    
    create_table :contract_dependencies do |t|
      t.string :contract_artifact_init_code_hash, null: false
      t.string :dependency_init_code_hash, null: false
      t.integer :position, null: false
      
      if pg_adapter?
        t.check_constraint "contract_artifact_init_code_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "dependency_init_code_hash ~ '^0x[a-f0-9]{64}$'"
      end

      t.foreign_key :contract_artifacts, column: :contract_artifact_init_code_hash, primary_key: :init_code_hash, on_delete: :cascade
      t.foreign_key :contract_artifacts, column: :dependency_init_code_hash, primary_key: :init_code_hash, on_delete: :cascade
      
      t.timestamps
    end
    
    add_index :contract_dependencies,
      [:contract_artifact_init_code_hash, :dependency_init_code_hash],
      unique: true, name: 'index_contract_dependencies_on_artifact_and_dependency'
    
    add_index :contract_dependencies, [:contract_artifact_init_code_hash, :position], unique: true, name: 'index_contract_dependencies_on_artifact_and_position'
  end
  
  def down
    drop_table :contract_dependencies
    
    create_table :contract_artifacts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :internal_transaction_index, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.string :name, null: false
      t.text :source_code, null: false
      t.string :init_code_hash, null: false
      t.column :references, :jsonb, default: [], null: false
      t.string :pragma_language, null: false
      t.string :pragma_version, null: false
    
      t.index [:block_number, :transaction_index, :internal_transaction_index], unique: true
      t.index [:transaction_hash, :internal_transaction_index], unique: true
      t.index :init_code_hash, unique: true
      t.index :name
    
      if pg_adapter?
        t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
      end
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
  end
end
