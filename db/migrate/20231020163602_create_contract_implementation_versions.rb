class CreateContractImplementationVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_implementation_versions do |t|
      t.string :transaction_hash, null: false
      t.string :init_code_hash, null: false
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.bigint :internal_transaction_index, null: false
      t.string :contract_address, null: false
      
      t.index [:block_number, :transaction_index]
      t.index :contract_address
      t.index [:internal_transaction_index, :transaction_hash], unique: true
      t.index :internal_transaction_index
      t.index :transaction_hash
      
      t.check_constraint "contract_address::text ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "transaction_hash::text ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "init_code_hash::text ~ '^[a-f0-9]{64}$'"
      
      t.foreign_key "contracts", column: "contract_address", primary_key: "address", on_delete: :cascade
      t.foreign_key "ethscriptions", column: "transaction_hash", primary_key: "ethscription_id", on_delete: :cascade    

      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION update_current_init_code_hash() RETURNS TRIGGER AS $$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          UPDATE contracts
          SET current_init_code_hash = (
            SELECT init_code_hash
            FROM contract_implementation_versions
            WHERE contract_address = NEW.contract_address
            ORDER BY block_number DESC, transaction_index DESC, internal_transaction_index DESC
            LIMIT 1
          )
          WHERE address = NEW.contract_address;
        ELSIF TG_OP = 'DELETE' THEN
          UPDATE contracts
          SET current_init_code_hash = (
            SELECT init_code_hash
            FROM contract_implementation_versions
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
      
      CREATE TRIGGER update_current_init_code_hash
      AFTER INSERT OR DELETE ON contract_implementation_versions
      FOR EACH ROW EXECUTE PROCEDURE update_current_init_code_hash();
    SQL
  end
end
