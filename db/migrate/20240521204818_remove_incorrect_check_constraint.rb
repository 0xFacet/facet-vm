class RemoveIncorrectCheckConstraint < ActiveRecord::Migration[7.1]
  def change
    remove_check_constraint :transaction_receipts, name: "chk_rails_f9b075c036"
  end
end
