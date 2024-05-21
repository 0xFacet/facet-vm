class BlockBatchContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :contracts, :contract_classes
  
  def get_contract_class(init_code_hash)
    contract_classes[init_code_hash]
  end
  
  def get_existing_contract_batch(addresses)
    in_memory = addresses.map { |a| contracts[a] }.compact
    
    need_to_fetch = addresses - in_memory.map(&:address)
    
    from_db = Contract.where(deployed_successfully: true, address: need_to_fetch)
    
    artifacts = ContractArtifact.where(init_code_hash: from_db.map(&:current_init_code_hash)).index_by(&:init_code_hash)
    
    from_db.each do |c|
      contracts[c.address] = c
      
      artifact = artifacts[c.current_init_code_hash]
      
      contract_classes[c.current_init_code_hash] ||= artifact&.build_class
    end
    
    (in_memory + from_db)
  end
  
  def get_existing_contract(address)
    get_existing_contract_batch([address]).first
  end
end
