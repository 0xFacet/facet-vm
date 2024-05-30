class RemoveCheckConstraintFromTransactionReceipts < ActiveRecord::Migration[7.1]
  def up
    if constraint_exists?('transaction_receipts', 'chk_rails_4a6d0a1199')
      remove_check_constraint :transaction_receipts, name: 'chk_rails_4a6d0a1199'
    end

    if constraint_exists?('transaction_receipts', 'chk_rails_f9b075c036')
      remove_check_constraint :transaction_receipts, name: 'chk_rails_f9b075c036'
    end
  end

  def down
  end

  private

  def constraint_exists?(table_name, constraint_name)
    query = <<-SQL
      SELECT EXISTS (
        SELECT 1
        FROM information_schema.constraint_table_usage
        WHERE table_name = '#{table_name}'
          AND constraint_name = '#{constraint_name}'
      )
    SQL

    ActiveRecord::Base.connection.execute(query).first['exists']
  end
end