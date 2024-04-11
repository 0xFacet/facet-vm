class CreateContractStates < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_states, force: :cascade do |t|
      t.string :type, null: false
      t.string :init_code_hash, null: false
      t.column :state, :jsonb, default: {}, null: false
      t.bigint :block_number, null: false
      t.string :contract_address, null: false
    
      t.index :block_number
      t.index :contract_address
    
      if pg_adapter?
        t.check_constraint "contract_address ~ '^0x[a-f0-9]{40}$'"
        t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
      end
    
      t.foreign_key :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
    
    return unless pg_adapter?
        
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_current_state() RETURNS TRIGGER AS $$
      DECLARE
        latest_contract_state RECORD;
        state_count INTEGER;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = NEW.contract_address
          ORDER BY block_number DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash,
              updated_at = NOW()
          WHERE address = NEW.contract_address;
        ELSIF TG_OP = 'DELETE' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = OLD.contract_address
            AND id != OLD.id
          ORDER BY block_number DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash,
              updated_at = NOW()
          WHERE address = OLD.contract_address;
        END IF;
      
        RETURN NULL; -- result is ignored since this is an AFTER trigger
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER update_current_state
      AFTER INSERT OR DELETE ON contract_states
      FOR EACH ROW EXECUTE PROCEDURE update_current_state();
    SQL
    
    execute <<~SQL
      CREATE OR REPLACE FUNCTION check_last_state() RETURNS TRIGGER AS $$
      DECLARE
        state_count INTEGER;
      BEGIN
        SELECT COUNT(*) INTO state_count
        FROM contract_states
        WHERE contract_address = OLD.contract_address;

        IF state_count = 1 THEN
          RAISE EXCEPTION 'Cannot delete the last state of a contract.';
        END IF;

        RETURN OLD; -- In a BEFORE trigger, returning OLD allows the operation to proceed
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER check_before_delete
      BEFORE DELETE ON contract_states
      FOR EACH ROW EXECUTE PROCEDURE check_last_state();
    SQL
  end
end
