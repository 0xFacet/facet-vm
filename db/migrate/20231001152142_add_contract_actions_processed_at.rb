class AddContractActionsProcessedAt < ActiveRecord::Migration[7.0]
  def up
    EthBlock.delete_all
    
    add_column :ethscriptions, :contract_actions_processed_at, :datetime
    add_column :eth_blocks, :processing_state, :string, null: false
    
    add_index :eth_blocks, :processing_state
    add_index :eth_blocks, :block_number, where: "processing_state = 'complete'", name: 'index_eth_blocks_on_block_number_completed'
    add_index :eth_blocks, :block_number, where: "processing_state = 'pending'", name: 'index_eth_blocks_on_block_number_pending'

    add_index :eth_blocks, [:imported_at, :processing_state]

    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_block_sequence()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.processing_state = 'complete' THEN
          IF EXISTS (
            SELECT 1
            FROM eth_blocks
            WHERE block_number < NEW.block_number
              AND processing_state = 'pending'
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER check_block_sequence_trigger
      BEFORE UPDATE OF processing_state ON eth_blocks
      FOR EACH ROW EXECUTE FUNCTION check_block_sequence();
    SQL
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_ethscription_sequence()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.contract_actions_processed_at IS NOT NULL THEN
          IF EXISTS (
            SELECT 1
            FROM ethscriptions
            WHERE 
              (block_number < NEW.block_number AND contract_actions_processed_at IS NULL)
              OR 
              (block_number = NEW.block_number AND transaction_index < NEW.transaction_index AND contract_actions_processed_at IS NULL)
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous ethscription with either a lower block number or a lower transaction index in the same block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER check_ethscription_sequence_trigger
      BEFORE UPDATE OF contract_actions_processed_at ON ethscriptions
      FOR EACH ROW EXECUTE FUNCTION check_ethscription_sequence();
    SQL
  end
  
  def down
    execute <<-SQL
      DROP TRIGGER check_block_sequence_trigger ON eth_blocks;
      DROP TRIGGER check_ethscription_sequence_trigger ON ethscriptions;
    SQL
  
    execute <<-SQL
      DROP FUNCTION check_block_sequence();
      DROP FUNCTION check_ethscription_sequence();
    SQL
    
    remove_index :eth_blocks, name: 'index_eth_blocks_on_block_number_completed'
    remove_index :eth_blocks, name: 'index_eth_blocks_on_block_number_pending'

    remove_column :ethscriptions, :contract_actions_processed_at, :datetime
    remove_column :eth_blocks, :processing_state, :string, null: false
  end
end
