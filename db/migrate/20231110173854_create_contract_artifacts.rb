class CreateContractArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_artifacts do |t|
      t.string :name, null: false
      t.text :source_code, null: false
      t.text :ast, null: false
      t.string :init_code_hash, null: false
      t.jsonb :references, null: false, default: {}
      
      t.index :name, unique: true
      t.index :init_code_hash, unique: true
      
      t.check_constraint "init_code_hash ~ '^[a-f0-9]{64}$'"
      
      t.timestamps
    end
  end
end
