Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.table_exists?('contract_artifacts')
    ContractArtifact.all_contract_classes
  end
end
