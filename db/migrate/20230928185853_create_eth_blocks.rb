class CreateEthBlocks < ActiveRecord::Migration[7.0]
  def up
    create_table :eth_blocks, force: :cascade do |t|
      t.bigint :block_number, null: false
      t.bigint :timestamp, null: false
      t.string :blockhash, null: false
      t.string :parent_blockhash, null: false
      t.datetime :imported_at, null: false

      t.index :blockhash, unique: true
      t.index :parent_blockhash, unique: true
      t.index :block_number, unique: true
      t.index :imported_at
      
      t.check_constraint "blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "parent_blockhash ~ '^0x[a-f0-9]{64}$'"
      
      t.timestamps
    end
    
    add_foreign_key :ethscriptions, :eth_blocks, column: :block_number, primary_key: "block_number", on_delete: :cascade
    
    change_column :ethscriptions, :creation_timestamp, 'bigint USING EXTRACT(EPOCH FROM creation_timestamp)'
    
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
  end
  
  def down
    drop_table :eth_blocks
    
    change_column :ethscriptions, :creation_timestamp, 'timestamp USING to_timestamp(creation_timestamp)'
  end
end
