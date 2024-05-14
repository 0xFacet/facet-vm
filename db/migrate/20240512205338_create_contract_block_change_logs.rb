class CreateContractBlockChangeLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_block_change_logs do |t|
      t.bigint :block_number, null: false
      t.string :contract_address, null: false
      t.column :state_changes, :jsonb, default: {}, null: false
      
      t.index [:block_number, :contract_address], unique: true
      t.index :contract_address
      
      # t.timestamps
      
      t.timestamp :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
