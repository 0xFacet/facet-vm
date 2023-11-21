class CreateTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :transaction_receipts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.string :from_address, null: false
      t.string :status, null: false
      t.string :function
      t.jsonb :args, default: {}, null: false
      t.jsonb :logs, default: [], null: false
      t.bigint :block_timestamp, null: false
      t.jsonb :error
      t.string :effective_contract_address
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.string :block_blockhash, null: false
      t.jsonb :return_value
      t.integer :runtime_ms, null: false
      t.string :call_type, null: false
      t.bigint :gas_price
      t.bigint :gas_used
      t.bigint :transaction_fee
    
      t.index [:block_number, :transaction_index], unique: true, name: :index_contract_tx_receipts_on_block_number_and_tx_index
      t.index :effective_contract_address
      t.index :transaction_hash, unique: true
    
      t.check_constraint "effective_contract_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "status IN ('success', 'failure')"
      
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :transaction_hash, on_delete: :cascade
      t.foreign_key :eth_blocks, column: :block_number, primary_key: :block_number, on_delete: :cascade
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_status()
      RETURNS TRIGGER AS $$
      DECLARE
        call_status TEXT;
      BEGIN
        SELECT status INTO call_status FROM contract_calls WHERE transaction_hash = NEW.transaction_hash AND internal_transaction_index = 0;
        IF NEW.status <> call_status THEN
          RAISE EXCEPTION 'Receipt status must equal the status of the corresponding call';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER check_status_trigger
      BEFORE INSERT OR UPDATE OF status ON transaction_receipts
      FOR EACH ROW EXECUTE FUNCTION check_status();
    SQL
  end
end
