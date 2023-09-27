class AddLatestStateToContracts < ActiveRecord::Migration[7.0]
  def up
    add_column :contracts, :latest_state, :jsonb, null: false, default: {}
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_latest_state() RETURNS TRIGGER AS $$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          UPDATE contracts
          SET latest_state = (
            SELECT state
            FROM contract_states
            WHERE contract_address = NEW.contract_address
            ORDER BY block_number DESC, transaction_index DESC, internal_transaction_index DESC
            LIMIT 1
          )
          WHERE address = NEW.contract_address;
        ELSIF TG_OP = 'DELETE' THEN
          UPDATE contracts
          SET latest_state = (
            SELECT state
            FROM contract_states
            WHERE contract_address = OLD.contract_address
              AND id != OLD.id
            ORDER BY block_number DESC, transaction_index DESC, internal_transaction_index DESC
            LIMIT 1
          )
          WHERE address = OLD.contract_address;
        END IF;
      
        RETURN NULL; -- result is ignored since this is an AFTER trigger
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER update_latest_state
      AFTER INSERT OR DELETE ON contract_states
      FOR EACH ROW EXECUTE PROCEDURE update_latest_state();
    SQL
  end
  
  def down
    remove_column :contracts, :latest_state
    
    execute <<-SQL
      DROP TRIGGER update_latest_state ON contract_states;
      DROP FUNCTION update_latest_state;
    SQL
  end
end
