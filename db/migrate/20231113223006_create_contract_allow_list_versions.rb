class CreateContractAllowListVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_allow_list_versions do |t|
      t.references :ethscription, null: false, type: :string, foreign_key: {
        to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
      }
      
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      
      t.jsonb :allow_list, default: [], null: false
      
      t.index [:block_number, :transaction_index], unique: true
      t.timestamps
    end
  end
end
