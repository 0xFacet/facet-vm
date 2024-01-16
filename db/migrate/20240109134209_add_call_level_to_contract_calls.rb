class AddCallLevelToContractCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :contract_calls, :call_level, :string, null: false, default: 'high'
    
    add_check_constraint :contract_calls, "
      (call_type = 'create' AND call_level = 'high') OR
      (call_type = 'call' AND call_level IN ('high', 'low'))
    "
    
    change_column_default :contract_calls, :call_level, from: "high", to: nil
  end
end
