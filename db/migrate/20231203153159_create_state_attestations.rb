class CreateStateAttestations < ActiveRecord::Migration[7.1]
  def change
    create_table :state_attestations do |t|
      t.bigint :block_number, null: false
      t.string :state_hash, null: false
      t.string :parent_state_hash
      
      t.index :block_number, unique: true
      t.index :state_hash, unique: true
      t.index :parent_state_hash, unique: true
      
      t.check_constraint "state_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "parent_state_hash IS NULL OR parent_state_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_attestation_order()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (SELECT MAX(block_number) FROM state_attestations) IS NOT NULL THEN
          IF NEW.block_number <> (SELECT MAX(block_number) + 1 FROM state_attestations) THEN
            RAISE EXCEPTION 'New block number must be equal to max block number + 1';
          END IF;
          IF NEW.parent_state_hash <> (SELECT state_hash FROM state_attestations WHERE block_number = NEW.block_number - 1) THEN
            RAISE EXCEPTION 'Parent state hash must match the state hash of the previous block';
          END IF;
        ELSE
          IF NEW.parent_state_hash IS NOT NULL THEN
            RAISE EXCEPTION 'Parent state hash of the first record must be NULL';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_check_attestation_order
      BEFORE INSERT ON state_attestations
      FOR EACH ROW EXECUTE FUNCTION check_attestation_order();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_block_processing_state()
      RETURNS TRIGGER AS $$
      BEGIN
        IF (SELECT processing_state FROM eth_blocks WHERE block_number = NEW.block_number) = 'pending' THEN
          RAISE EXCEPTION 'Cannot create a StateAttestation for a block with processing state pending';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_check_block_processing_state
      BEFORE INSERT ON state_attestations
      FOR EACH ROW EXECUTE FUNCTION check_block_processing_state();
    SQL
  end
end
