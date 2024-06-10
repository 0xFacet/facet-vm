class RemoveCheckLastStateTriggerAndFunction < ActiveRecord::Migration[7.1]
  def up
    return unless pg_adapter?
    
    execute <<-SQL
      DROP TRIGGER IF EXISTS check_before_delete ON contract_states;
      DROP FUNCTION IF EXISTS check_last_state();
    SQL
  end

  def down
    return unless pg_adapter?
    
    execute <<-SQL
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
