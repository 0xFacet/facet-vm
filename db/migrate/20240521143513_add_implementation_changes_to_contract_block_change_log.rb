class AddImplementationChangesToContractBlockChangeLog < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_block_change_logs, :implementation_change, :jsonb, null: false, default: {}
  end
end
