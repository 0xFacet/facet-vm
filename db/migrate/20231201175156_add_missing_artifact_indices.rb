class AddMissingArtifactIndices < ActiveRecord::Migration[7.1]
  def change
    add_index :contract_artifacts, :transaction_hash, unique: true
    add_index :contract_artifacts, [:block_number, :transaction_index], unique: true
  end
end
