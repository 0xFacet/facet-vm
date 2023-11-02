class AddTimestampIndexToEthBlocks < ActiveRecord::Migration[7.1]
  def change
    add_index :eth_blocks, :timestamp
  end
end
