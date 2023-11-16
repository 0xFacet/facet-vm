class CreateEthscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :ethscriptions, force: :cascade do |t|
      t.string :ethscription_id, null: false
      t.bigint :block_number, null: false
      t.string :block_blockhash, null: false
      t.bigint :transaction_index, null: false
      t.string :creator, null: false
      t.string :initial_owner, null: false
      t.bigint :creation_timestamp, null: false
      t.text :content_uri, null: false
      t.string :mimetype, null: false
      t.datetime :contract_actions_processed_at
      t.decimal :gas_price
      t.decimal :gas_used
      t.decimal :transaction_fee
      
      t.index [:block_number, :transaction_index], unique: true
      t.index :ethscription_id, unique: true
    
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "creator ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "ethscription_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "initial_owner ~ '^0x[a-f0-9]{40}$'"
    
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end    
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION delete_later_ethscriptions()
      RETURNS TRIGGER AS $$
      BEGIN
        DELETE FROM ethscriptions WHERE block_number > OLD.block_number OR (block_number = OLD.block_number AND transaction_index > OLD.transaction_index);
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_delete_later_ethscriptions
      AFTER DELETE ON ethscriptions
      FOR EACH ROW EXECUTE FUNCTION delete_later_ethscriptions();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_ethscription_order()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
          RAISE EXCEPTION 'New ethscription must be later in order';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_check_ethscription_order
      BEFORE INSERT ON ethscriptions
      FOR EACH ROW EXECUTE FUNCTION check_ethscription_order();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_ethscription_sequence()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.contract_actions_processed_at IS NOT NULL THEN
          IF EXISTS (
            SELECT 1
            FROM ethscriptions
            WHERE 
              (block_number < NEW.block_number AND contract_actions_processed_at IS NULL)
              OR 
              (block_number = NEW.block_number AND transaction_index < NEW.transaction_index AND contract_actions_processed_at IS NULL)
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous ethscription with either a lower block number or a lower transaction index in the same block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER check_ethscription_sequence_trigger
      BEFORE UPDATE OF contract_actions_processed_at ON ethscriptions
      FOR EACH ROW EXECUTE FUNCTION check_ethscription_sequence();
    SQL
  end
end
