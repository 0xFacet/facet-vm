class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  if ENV['DATABASE_REPLICA_URL'].present?
    connects_to database: { writing: :primary, reading: :primary_replica }
  else
    connects_to database: { writing: :primary }
  end
  
  private
  
  def self.with_temporary_database_environment
    original_connection_config = ActiveRecord::Base.connection_db_config.configuration_hash
    original_verbose = ActiveRecord::Migration.verbose
  
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ApplicationRecord.descendants.reject(&:abstract_class?).each do |model|
      model.reset_column_information if model.connected?
      model.reset_sequence_name
    end
  
    migrations_paths = Rails.root.join('db', 'migrate')
    context = ActiveRecord::MigrationContext.new(migrations_paths)
    context.migrate
  
    yield
  ensure
    ActiveRecord::Base.connection.close if ActiveRecord::Base.connection&.active?
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    ActiveRecord::Base.establish_connection(original_connection_config)
    ActiveRecord::Migration.verbose = original_verbose
    ApplicationRecord.descendants.reject(&:abstract_class?).each do |model|
      model.reset_column_information if model.connected?
      model.reset_sequence_name
    end
  end
  
  def using_postgres?
    ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql'
  end
end
