class CreateNewContractStates < ActiveRecord::Migration[7.1]
  def change
    create_table :new_contract_states do |t|
      t.string :contract_address, null: false
      t.column :key, :jsonb, null: false
      t.column :value, :jsonb, null: false

      t.timestamps
      
      t.index :contract_address
      t.index [:contract_address, :key], unique: true
      
      # t.index :key, using: :gin, opclass: :jsonb_path_ops
    end
  end
end
