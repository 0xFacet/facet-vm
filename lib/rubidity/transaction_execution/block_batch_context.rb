class BlockBatchContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :contracts, :contract_artifacts
  
  def get_contract_artifact!(init_code_hash)
    contract_artifacts[init_code_hash] ||= ContractArtifact.
      includes(contract_dependencies: :dependency).
      find_by(init_code_hash: init_code_hash)
      
    if contract_artifacts[init_code_hash]
      return contract_artifacts[init_code_hash]
    else
      raise ContractError, "Contract not found: #{init_code_hash}"
    end
  end
  
  def get_existing_contract_batch(addresses)
    in_memory = addresses.map { |a| contracts[a] }.compact
    
    need_to_fetch = addresses - in_memory.map(&:address)
    
    from_db = Contract.where(deployed_successfully: true, address: need_to_fetch)
    
    artifacts = ContractArtifact.
    includes(contract_dependencies: :dependency).
    where(init_code_hash: from_db.map(&:current_init_code_hash)).index_by(&:init_code_hash)
    
    from_db.each do |c|
      contracts[c.address] = c
      contract_artifacts[c.current_init_code_hash] = artifacts[c.current_init_code_hash]
    end
    
    (in_memory + from_db)
  end
  
  def get_existing_contract(address)
    get_existing_contract_batch([address]).first
  end
end
