class RemoveToContractTypeFromContractCalls < ActiveRecord::Migration[7.1]
  def change
    remove_column :contract_calls, :to_contract_type, :string
    remove_index :contract_artifacts, :name
    add_index :contract_artifacts, :name
  end
end
