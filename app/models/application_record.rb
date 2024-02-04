class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  if ENV['DATABASE_REPLICA_URL'].present?
    connects_to database: { writing: :primary, reading: :primary_replica }
  else
    connects_to database: { writing: :primary }
  end
end
