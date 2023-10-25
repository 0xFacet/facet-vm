class CreateContractStates < ActiveRecord::Migration[7.0]
  def change
    create_table :contract_states do |t|
      t.references :contract, null: false, type: :string, foreign_key: {
        to_table: :contracts, primary_key: 'contract_id', on_delete: :cascade
      }
      
      t.references :ethscription, null: false, type: :string, foreign_key: {
        to_table: :ethscriptions, primary_key: 'ethscription_id', on_delete: :cascade
      }
      
      t.string :type, null: false
      t.string :init_code_hash, null: false
      t.jsonb :state, default: {}, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      
      t.index [:block_number, :transaction_index]
      t.index :state, using: :gin
      
      t.timestamps
      
      t.check_constraint "contract_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "ethscription_id ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "init_code_hash::text ~ '^[a-f0-9]{64}$'"
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_current_state() RETURNS TRIGGER AS $$
      DECLARE
        latest_contract_state RECORD;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = NEW.contract_address
          ORDER BY block_number DESC, transaction_index DESC, internal_transaction_index DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash
          WHERE address = NEW.contract_address;
        ELSIF TG_OP = 'DELETE' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = OLD.contract_address
            AND id != OLD.id
          ORDER BY block_number DESC, transaction_index DESC, internal_transaction_index DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash
          WHERE address = OLD.contract_address;
        END IF;
      
        RETURN NULL; -- result is ignored since this is an AFTER trigger
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER update_current_state
      AFTER INSERT OR DELETE ON contract_states
      FOR EACH ROW EXECUTE PROCEDURE update_current_state();
    SQL
  end
end
