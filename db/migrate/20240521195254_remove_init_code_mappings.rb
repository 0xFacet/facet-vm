class RemoveInitCodeMappings < ActiveRecord::Migration[7.1]
  def change
    drop_table :init_code_mappings do |t|
      t.string :old_init_code_hash, null: false
      t.string :new_init_code_hash, null: false
      
      t.index :old_init_code_hash, unique: true
      t.index :new_init_code_hash, unique: true
      
      t.timestamps
    end
  end
end
