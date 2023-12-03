class RemoveIncorrectCheckConstraints < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :contract_calls, name: "chk_rails_028f647531"
    remove_check_constraint :contract_calls, name: "chk_rails_392c3d2c8e"
  end
  
  def down
    
  end
end
