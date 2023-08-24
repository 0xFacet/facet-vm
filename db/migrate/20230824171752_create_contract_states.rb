class CreateContractStates < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_states do |t|
      t.references :contract, null: false, type: :string, foreign_key: {
        to_table: :contracts, primary_key: 'contract_id', on_delete: :cascade
      }
      
      t.references :ethscription, null: false, type: :string, foreign_key: {
        to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
      }
      
      t.jsonb :state, default: {}, null: false
      t.bigint :block_number, null: false
      t.integer :transaction_index, null: false
      
      t.index [:block_number, :transaction_index]
      t.index :state, using: :gin
      
      t.timestamps
      
      t.check_constraint "contract_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "ethscription_id ~ '^0x[a-f0-9]{64}$'"
    end
  end
end
