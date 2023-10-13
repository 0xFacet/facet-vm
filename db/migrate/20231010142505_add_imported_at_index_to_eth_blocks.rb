class AddImportedAtIndexToEthBlocks < ActiveRecord::Migration[7.0]
  def change
    add_index :eth_blocks, [:imported_at, :processing_state]
  end
end
