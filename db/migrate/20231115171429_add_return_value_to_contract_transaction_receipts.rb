class AddReturnValueToContractTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_transaction_receipts, :return_value, :jsonb
  end
end
