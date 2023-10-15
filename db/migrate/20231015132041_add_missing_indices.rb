class AddMissingIndices < ActiveRecord::Migration[7.0]
  def change
    # TODO ordering should be over block number and tx index
    add_index :contract_transaction_receipts, [:transaction_hash, :created_at],
      name: "index_contract_transaction_receipts_on_tx_hash_and_created_at"
  end
end
