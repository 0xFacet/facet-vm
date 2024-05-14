class BlockContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :current_block, :system_config, :contract_artifacts,
    :contracts, :ethscriptions, :parsed_ethscriptions
  
  delegate :current_transaction, :current_call, to: TransactionContext
  
  def ethscriptions=(ethscriptions)
    self.parsed_ethscriptions = (ethscriptions || []).map do |e|
      e.process!(persist: false)
    end
    
    super(ethscriptions)
  end
  
  def contract_transactions
    (parsed_ethscriptions || []).map(&:contract_transaction).compact
  end
  
  def system_config_versions
    (parsed_ethscriptions || []).map(&:system_config_version).compact
  end
  
  def process!
    process_contract_transactions(persist: true)
    
    system_config_versions.each(&:save!)
    
    success_ethscriptions = parsed_ethscriptions.select { |e| e.processing_state == 'success' }
    failure_ethscriptions = parsed_ethscriptions.select { |e| e.processing_state == 'failure' }
  
    Ethscription.where(id: success_ethscriptions.map(&:id)).update_all(
      processing_state: 'success',
      processed_at: Time.current
    )
  
    if failure_ethscriptions.present?
      Ethscription.where(id: failure_ethscriptions.map(&:id)).update_all(
        processing_state: 'failure',
        processed_at: Time.current
      ) 
    end
  end
  
  def process_contract_transactions(persist:)
    initial_contracts = contract_transactions.map do |t|
      t.payload.dig('data', 'to')&.downcase
    end.uniq.compact
    
    Contract.where(address: initial_contracts, deployed_successfully: true).each do |contract|
      add_contract(contract)
    end
    
    self.contract_artifacts = ContractArtifact.where(
      init_code_hash: contracts.map(&:current_init_code_hash)
    ).to_a
    
    contract_transactions.each do |contract_tx|
      TransactionContext.set(
        call_stack: CallStack.new(TransactionContext),
        active_contracts: [],
        current_transaction: contract_tx,
        current_event_index: 0,
        tx_origin: contract_tx.tx_origin,
        tx_current_transaction_hash: contract_tx.transaction_hash,
        block_number: current_block.block_number,
        block_timestamp: current_block.timestamp,
        block_blockhash: current_block.blockhash,
        block_chainid: current_chainid,
        transaction_index: contract_tx.transaction_index
      ) do
        contract_tx.execute_transaction
      end
    end
    
    return unless persist
    
    ContractTransaction.import!(contract_transactions)
    
    TransactionReceipt.import!(
      contract_transactions.map(&:transaction_receipt_for_import)
    )
    
    ContractCall.import!(
      contract_transactions.flat_map{|i| i.contract_calls.target }
    )
    
    ContractArtifact.import!(contract_artifacts.select(&:new_record?))
    
    Contract.import!(contracts.select(&:new_record?))
    
    states_to_save = contracts.map do |c|
      c.new_state_for_save(block_number: current_block.block_number)
    end.compact
    
    ContractState.import!(states_to_save)
    
    states_to_save.each do |state|
      state.run_callbacks(:create)
    end
    
    contracts.each do |c|
      c.wrapper.persist(current_block.block_number)
    end
  end
  
  def start_block_passed?
    return unless system_config.start_block_number
    current_block.block_number >= system_config.start_block_number
  end
  
  def add_contract(contract)
    contracts << contract if contract
    contract&.initialize_state
    contract
  end
  
  def get_existing_contract(address)
    in_memory = contracts.detect do |contract|
      contract.deployed_successfully? &&
      contract.address == address
    end
    
    return in_memory if in_memory
    
    from_db = Contract.find_by(deployed_successfully: true, address: address)
    
    add_contract(from_db)
  end
  
  def create_new_contract(address:, init_code_hash:, source_code:)
    new_contract_implementation = BlockContext.supported_contract_class(
      init_code_hash,
      source_code
    )
    
    new_contract = Contract.new(
      transaction_hash: current_transaction.transaction_hash,
      block_number: current_block.block_number,
      transaction_index: current_transaction.transaction_index,
      address: address,
      current_type: new_contract_implementation.name,
      current_init_code_hash: init_code_hash
    )
    
    add_contract(new_contract)
  end
  
  def supported_contract_class(init_code_hash, source_code = nil, validate: true)
    validate_contract_support(init_code_hash) if validate
    
    find_and_build_class(init_code_hash) ||
      create_artifact_and_build_class(init_code_hash, source_code)
  end
  
  def current_chainid
    if ENV.fetch("ETHEREUM_NETWORK") == "eth-mainnet"
      1
    elsif ENV.fetch("ETHEREUM_NETWORK") == "eth-goerli"
      5
    elsif ENV.fetch("ETHEREUM_NETWORK") == "eth-sepolia"
      11155111
    else
      raise "Unknown network: #{ENV.fetch("ETHEREUM_NETWORK")}"
    end
  end
  
  def calculate_contract_nonce(address)
    in_this_block = previous_calls.select do |call|
      call.from_address == address &&
      call.is_create? &&
      call.success?
    end.count
    
    in_past_blocks = ContractCall.where(
      from_address: address,
      call_type: :create,
      status: :success
    ).where("block_number < ?", current_block.block_number).count
    
    in_this_block + in_past_blocks
  end
  
  def calculate_eoa_nonce(address)
    in_this_block = previous_transactions.select do |tx|
      tx.initial_call.from_address == address
    end.count
    
    in_past_blocks = ContractCall.where(
      from_address: address,
      call_type: [:create, :call]
    ).where("block_number < ?", current_block.block_number).count
    
    in_this_block + in_past_blocks
  end
  
  private
  
  def validate_contract_support(init_code_hash)
    unless system_config.contract_supported?(init_code_hash)
      raise ContractError.new("Contract is not supported: #{init_code_hash.inspect}")
    end
  end
  
  def get_cached_class(init_code_hash)
    attempt = ContractArtifact.cached_class_as_of_tx_hash(
      init_code_hash,
      current_transaction&.transaction_hash
    )
    
    return attempt if attempt
    
    init_code_hash = InitCodeMapping.old_to_new(init_code_hash)
    
    ContractArtifact.cached_class_as_of_tx_hash(
      init_code_hash,
      current_transaction&.transaction_hash
    )
  end
  
  def find_and_build_class(init_code_hash)
    unless current_block
      return get_cached_class(init_code_hash)
    end
    
    current = contract_artifacts.detect do |artifact|
      artifact.init_code_hash == init_code_hash ||
      artifact.init_code_hash == InitCodeMapping.old_to_new(init_code_hash)
    end
  
    current&.build_class || get_cached_class(init_code_hash)
  end
  
  def previous_transactions
    contract_transactions.select do |tx|
      tx.transaction_index < current_transaction.transaction_index
    end
  end
  
  def previous_calls
    previous_transactions.map(&:contract_calls).flatten +
    current_transaction.contract_calls.select do |call|
      call.internal_transaction_index < current_call.internal_transaction_index
    end
  end
    
  def create_artifact_and_build_class(init_code_hash, source_code = nil)
    unless source_code
      raise ContractSourceNotProvided.new("Need source code to create new artifact")
    end
  
    artifact = RubidityTranspiler.new(source_code).get_desired_artifact(init_code_hash)
    
    self.contract_artifacts << ContractArtifact.new(
      artifact.attributes.merge(
        block_number: current_block.block_number,
        transaction_hash: current_transaction.transaction_hash,
        transaction_index: current_transaction.transaction_index,
        internal_transaction_index: current_call.internal_transaction_index,
      )
    )
    
    artifact&.build_class
  end
end
