class AddForeignKeyToNewContractStates < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :new_contract_states, :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
    add_foreign_key :contract_block_change_logs, :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
  end
end
