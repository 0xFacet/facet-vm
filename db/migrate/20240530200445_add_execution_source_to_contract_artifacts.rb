class AddExecutionSourceToContractArtifacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_artifacts, :execution_source_code, :text
    add_column :contract_artifacts, :serialized_ast, :binary
  end
end
