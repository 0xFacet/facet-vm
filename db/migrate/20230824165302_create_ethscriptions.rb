class CreateEthscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :ethscriptions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.string :block_blockhash, null: false
      t.bigint :transaction_index, null: false
      t.string :creator, null: false
      t.string :initial_owner, null: false
      t.bigint :block_timestamp, null: false
      t.text :content_uri, null: false
      t.string :mimetype, null: false
      t.datetime :processed_at
      t.string :processing_state, null: false
      t.string :processing_error
      t.bigint :gas_price
      t.bigint :gas_used
      t.bigint :transaction_fee
      
      t.index :block_number
      t.index [:block_number, :transaction_index], unique: true
      t.index :transaction_hash, unique: true
      t.index :processing_state
    
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "creator ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "initial_owner ~ '^0x[a-f0-9]{40}$'"
    
      t.check_constraint "processing_state IN ('pending', 'success', 'failure')"
      
      # t.check_constraint "processing_state != 'failure' OR processing_error IS NOT NULL"
      t.check_constraint "processing_state = 'pending' OR processed_at IS NOT NULL"
      # t.check_constraint "processing_state = 'failure' OR processing_error IS NULL"
      
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end

    # TODO
    
    # execute <<-SQL
    #   CREATE OR REPLACE FUNCTION check_ethscription_order()
    #   RETURNS TRIGGER AS $$
    #   BEGIN
    #     IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
    #       RAISE EXCEPTION 'New ethscription must be later in order';
    #     END IF;
    #     RETURN NEW;
    #   END;
    #   $$ LANGUAGE plpgsql;

    #   CREATE TRIGGER trigger_check_ethscription_order
    #   BEFORE INSERT ON ethscriptions
    #   FOR EACH ROW EXECUTE FUNCTION check_ethscription_order();
    # SQL
  end
end
