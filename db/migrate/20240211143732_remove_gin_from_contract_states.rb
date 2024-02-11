class RemoveGinFromContractStates < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :contract_states, :state, using: :gin, algorithm: :concurrently
    remove_index :contracts, :current_state, using: :gin, algorithm: :concurrently
  end
end
