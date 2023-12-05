class CreateContractStates < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_states, force: :cascade do |t|
      # t.string :transaction_hash, null: false
      t.string :type, null: false
      t.string :init_code_hash, null: false
      t.jsonb :state, default: {}, null: false
      t.bigint :block_number, null: false
      # t.bigint :transaction_index, null: false
      t.string :contract_address, null: false
    
      t.index :block_number
      t.index [:contract_address, :block_number], unique: true
      # t.index [:contract_address, :transaction_hash], unique: true
      # t.index [:contract_address, :block_number, :transaction_index], unique: true,
      #   name: :index_contract_states_on_addr_block_number_tx_index
      t.index :contract_address
      t.index :state, using: :gin
      # t.index :transaction_hash
    
      t.check_constraint "contract_address ~ '^0x[a-f0-9]{40}$'"
      # t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "init_code_hash ~ '^0x[a-f0-9]{64}$'"
    
      # t.foreign_key :contracts, column: :contract_address, primary_key: :address, on_delete: :cascade
      # t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
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
          ORDER BY block_number DESC--, transaction_index DESC
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
          ORDER BY block_number DESC--, transaction_index DESC
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
