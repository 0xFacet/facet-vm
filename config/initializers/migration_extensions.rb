module MigrationExtensions
  def sqlite_adapter?
    ActiveRecord::Base.connection.adapter_name.downcase == 'sqlite3'
  end

  def pg_adapter?
    ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
  end
end

ActiveRecord::Migration.prepend(MigrationExtensions)
