class AddProcessingStateIndexToEthBlocksAndFromAddressOnReceipts < ActiveRecord::Migration[7.1]
  def change
    add_index :transaction_receipts, :from_address

    add_index :eth_blocks, :blockhash,
      where: "processing_state != 'pending'",
      name: "index_eth_blocks_on_blockhash_and_processing_state"
  end
end
