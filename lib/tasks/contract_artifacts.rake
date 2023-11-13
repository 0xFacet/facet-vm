namespace :contract_artifacts do
  desc "Load all contract classes"
  task load: :environment do
    if ActiveRecord::Base.connection.table_exists?('contract_artifacts')
      require Rails.root.join('app', 'models', 'boolean_extensions.rb')

      ContractArtifact.all_contract_classes
    end
  end
end
