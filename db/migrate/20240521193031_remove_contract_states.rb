class RemoveContractStates < ActiveRecord::Migration[7.1]
  def change
    drop_table :contract_states
    
    create_table :contract_states, force: :cascade do |t|
      t.string :type, null: false
      t.string :init_code_hash, null: false
      t.column :state, :jsonb, default: {}
      t.bigint :block_number, null: false
      t.string :contract_address, null: false
    
      t.index :block_number
      t.index :contract_address
    
      if pg_adapter?
        t.check_constraint "contract_address ~ '^0x[a-f0-9]{40}$'"
        t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
      end
    
      t.foreign_key :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
  end
end
