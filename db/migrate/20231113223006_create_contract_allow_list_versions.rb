class CreateContractAllowListVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_allow_list_versions do |t|
      t.string :transaction_hash, null: false

      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      
      t.jsonb :allow_list, default: [], null: false
      
      t.index :transaction_hash, unique: true
      t.index [:block_number, :transaction_index], unique: true
      
      t.foreign_key :ethscriptions, column: :transaction_hash,
        primary_key: :ethscription_id, on_delete: :cascade
            
      t.timestamps
    end
  end
end
