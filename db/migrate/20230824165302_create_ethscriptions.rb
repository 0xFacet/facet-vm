class CreateEthscriptions < ActiveRecord::Migration[7.0]
  def up
    create_table :ethscriptions do |t|
      t.string :ethscription_id, null: false
      t.bigint :block_number, null: false
      t.integer :transaction_index, null: false
      t.bigint :ethscription_number
      t.string :creator, null: false
      t.string :initial_owner, null: false
      t.string :current_owner, null: false
      t.datetime :creation_timestamp, null: false
      t.string :previous_owner
      t.text :content_uri, null: false
      t.string :content_sha, null: false
      t.string :mimetype, null: false

      t.index :ethscription_id, unique: true
      t.index :content_sha, unique: true
      t.index [:block_number, :transaction_index], unique: true
      
      t.timestamps
      
      t.check_constraint "ethscription_id ~ '^0x[a-f0-9]{64}$'", name: 'ethscriptions_ethscription_id_format'
      t.check_constraint "creator ~ '^0x[a-f0-9]{40}$'", name: 'ethscriptions_creator_format'
      t.check_constraint "current_owner ~ '^0x[a-f0-9]{40}$'", name: 'ethscriptions_current_owner_format'
      t.check_constraint "initial_owner ~ '^0x[a-f0-9]{40}$'", name: 'ethscriptions_initial_owner_format'
      t.check_constraint "previous_owner IS NULL OR previous_owner ~ '^0x[a-f0-9]{40}$'", name: 'ethscriptions_previous_owner_format'
      t.check_constraint "content_sha ~ '^[a-f0-9]{64}$'", name: 'ethscriptions_content_sha_format'
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

  end
  
  def down
    drop_table :ethscriptions
  end
end
