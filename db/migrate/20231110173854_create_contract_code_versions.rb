class CreateContractCodeVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_code_versions do |t|
      t.string :name, null: false, index: { unique: true }
      t.text :source_code, null: false
      t.text :ast, null: false
      t.string :init_code_hash, null: false, index: { unique: true }
      t.string :source_file, null: false
      
      t.check_constraint "init_code_hash ~ '^[a-f0-9]{64}$'"
      
      t.timestamps
    end
  end
end
