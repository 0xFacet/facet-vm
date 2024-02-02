class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  if ENV['REPLICA_DATABASE_URL'].present?
    connects_to database: { writing: :primary, reading: :primary_replica }
  end
end
