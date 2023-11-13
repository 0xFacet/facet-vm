Rails.application.reloader.to_prepare do
  if ActiveRecord::Base.connection.table_exists?('contract_artifacts')
    ContractArtifact.reset
  end
end
