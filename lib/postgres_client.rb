class PostgresClient
  DB_USER = `whoami`.chomp
  DATABASE_THATS_ALWAYS_THERE = 'postgres'
  
  ACTUAL_DATABASE_NAME = if ENV['DATABASE_URL']
    URI.parse(ENV['DATABASE_URL']).path[1..-1]
  else
    Rails.configuration.database_configuration.dig("development", "database")
  end
  
  SWAP_IN_DATABASE_NAME = "#{ACTUAL_DATABASE_NAME}-fresh"
  SWAP_OUT_DATABASE_NAME = "#{ACTUAL_DATABASE_NAME}-old"
  
  def self.random_database_name
    "#{SWAP_IN_DATABASE_NAME}-random-#{SecureRandom.hex(5)}"
  end
  
  def self.swap_in_database_name(version: 1)
    "#{SWAP_IN_DATABASE_NAME}-v#{version}"
  end
  
  def self.freshest_db
    swap_in_database_name(version: smallest_unused_version_number - 1)
  end
  
  def self.first_free_name
    swap_in_database_name(version: smallest_unused_version_number)
  end
  
  def self.smallest_unused_version_number
    return 1 if existing_versioned_names.blank?
    existing_versioned_names.last[/\d+/].to_i + 1
  end
  
  def self.db_exists?(db_name)
    new.db_exists?(db_name)
  end
  
  def self.existing_versioned_names
    matches = `psql -l`.scan(/#{Regexp.escape(SWAP_IN_DATABASE_NAME)}-v\d+/)
        
    matches.sort_by do |match|
      match[/\d+/].to_i
    end
  end
  
  def self.stale_dbs
    existing_versioned_names - existing_versioned_names.last(5)
  end
  
  def db_exists?(db_name)
    `psql -l`.include?(" #{db_name} ")
  end
  
  def restore!
    random_db = self.class.random_database_name
    
    puts "Pulling into #{random_db}"
    run_shell_command %{heroku pg:pull DATABASE_URL #{random_db} -a #{ENV.fetch("HEROKU_APP_NAME")}}
    
    new_name = self.class.first_free_name
    puts "Renaming to #{random_db} to #{new_name}"
    run_psql_command %{ALTER DATABASE "#{random_db}" RENAME TO "#{new_name}"}
    
    drop_db_if_exists!(random_db)
    
    self.class.stale_dbs.each do |db|
      puts "Dropping #{db}"
      drop_db_if_exists!(db)
    end
  end
  
  def swap_in!
    puts "Swapping in #{self.class.freshest_db}"
    drop_db_if_exists!(ACTUAL_DATABASE_NAME)
    run_psql_command %{ALTER DATABASE "#{self.class.freshest_db}" RENAME TO "#{ACTUAL_DATABASE_NAME}"}
  end

  def development_db_exists?
    db_exists?(ACTUAL_DATABASE_NAME)
  end

  def create_development_database!
    create_database!(ACTUAL_DATABASE_NAME)
  end

  def create_database!(database_name)
    if db_exists?(database_name)
      abort "It looks like #{database_name.inspect} database already exists"
    end

    run_shell_command %{createdb --encoding UTF-8 --owner #{DB_USER} #{database_name}}
  end

  private

  def run_shell_command(command, options = {})
    `#{command} 2>&1`.tap do |result|
      unless $? == 0
        STDERR.puts "Error running command #{command}, errors:\n #{result}"
        abort unless options[:rescue]
      end
    end
  end

  def run_psql_command(command)
    run_shell_command "psql -c '#{command};' -U #{DB_USER} -d #{DATABASE_THATS_ALWAYS_THERE}"
  end

  def drop_db_if_exists!(db_name)
    run_shell_command "dropdb '#{db_name}'" if db_exists?(db_name)
  end
end
