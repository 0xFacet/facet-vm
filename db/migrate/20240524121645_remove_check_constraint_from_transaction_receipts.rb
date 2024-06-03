class RemoveCheckConstraintFromTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    begin
      remove_check_constraint :transaction_receipts, name: "chk_rails_4a6d0a1199"
    rescue StandardError => e
      if e.message.include?("has no check constraint")
      else
        raise
      end
    end
    
    begin
      remove_check_constraint :transaction_receipts, name: "chk_rails_f9b075c036"
    rescue StandardError => e
      if e.message.include?("has no check constraint")
      else
        raise
      end
    end
  end
end
