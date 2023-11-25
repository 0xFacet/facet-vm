class CreateEthBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_blocks, force: :cascade do |t|
      t.bigint :block_number, null: false
      t.bigint :timestamp, null: false
      t.string :blockhash, null: false
      t.string :parent_blockhash, null: false
      t.datetime :imported_at, null: false
      t.string :processing_state, null: false
      t.bigint :transaction_count
    
      t.index :block_number, unique: true
      t.index :block_number, where: "(processing_state = 'complete')", name: "index_eth_blocks_on_block_number_completed"
      t.index :block_number, where: "(processing_state = 'pending')", name: "index_eth_blocks_on_block_number_pending"
      t.index :blockhash, unique: true
      t.index [:imported_at, :processing_state]
      t.index :imported_at
      t.index :parent_blockhash, unique: true
      t.index :processing_state
      t.index :timestamp
    
      t.check_constraint "blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "parent_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "processing_state <> 'complete' OR transaction_count IS NOT NULL"
      t.check_constraint "processing_state IN ('no_ethscriptions', 'pending', 'complete')"
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_block_order()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (SELECT MAX(block_number) FROM eth_blocks) IS NOT NULL AND (NEW.block_number <> (SELECT MAX(block_number) + 1 FROM eth_blocks) OR NEW.parent_blockhash <> (SELECT blockhash FROM eth_blocks WHERE block_number = NEW.block_number - 1)) THEN
          RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER trigger_check_block_order
      BEFORE INSERT ON eth_blocks
      FOR EACH ROW EXECUTE FUNCTION check_block_order();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION delete_later_blocks()
      RETURNS TRIGGER AS $$
      BEGIN
        DELETE FROM eth_blocks WHERE block_number > OLD.block_number;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_delete_later_blocks
      AFTER DELETE ON eth_blocks
      FOR EACH ROW EXECUTE FUNCTION delete_later_blocks();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_block_sequence()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.processing_state = 'complete' THEN
          IF EXISTS (
            SELECT 1
            FROM eth_blocks
            WHERE block_number < NEW.block_number
              AND processing_state = 'pending'
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER check_block_sequence_trigger
      BEFORE UPDATE OF processing_state ON eth_blocks
      FOR EACH ROW EXECUTE FUNCTION check_block_sequence();
    SQL
  end
end
