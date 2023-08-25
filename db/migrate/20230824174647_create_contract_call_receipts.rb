class CreateContractCallReceipts < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_call_receipts do |t|
      t.references :contract, null: true, type: :string, foreign_key: {
        to_table: :contracts, primary_key: 'contract_id', on_delete: :cascade
      }
      
      t.references :ethscription, null: false, type: :string, foreign_key: {
        to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
      }
      
      t.string :caller, null: false
      t.integer :status, null: false
      t.string :function_name
      t.jsonb :function_args, default: {}, null: false
      t.jsonb :logs, default: [], null: false
      t.datetime :timestamp, null: false
      t.string :error_message
      
      t.timestamps
      
      t.check_constraint "contract_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "ethscription_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "caller ~ '^0x[a-f0-9]{40}$'"
    end
  end
end
