class CreateContractBlockChangeLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_block_change_logs do |t|
      t.string :contract_address, null: false
      t.bigint :block_number, null: false
      t.column :state_changes, :jsonb, null: false

      t.timestamps
      
      t.index :contract_address
      t.index [:contract_address, :block_number], unique: true
    end
  end
end
