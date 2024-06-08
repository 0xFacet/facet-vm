class ContractDependency < ApplicationRecord
  belongs_to :contract_artifact, foreign_key: :contract_artifact_init_code_hash, primary_key: :init_code_hash, class_name: 'ContractArtifact', inverse_of: :contract_dependencies
  belongs_to :dependency, foreign_key: :dependency_init_code_hash, primary_key: :init_code_hash, class_name: 'ContractArtifact', inverse_of: :dependent_contract_dependencies
end
