class BlockContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :current_block, :system_config, :contract_artifacts,
    :contracts, :ethscriptions, :parsed_ethscriptions, :current_log_index
  
  delegate :current_transaction, :current_call, to: TransactionContext
  
  def ethscriptions=(ethscriptions)
    self.parsed_ethscriptions = (ethscriptions || []).map do |e|
      e.process!(persist: false)
    end
    
    super(ethscriptions)
  end
  
  def get_and_increment_log_index
    current = current_log_index
    self.current_log_index += 1
    
    current
  end
  
  def contract_transactions
    (parsed_ethscriptions || []).map(&:contract_transaction).compact
  end
  
  def system_config_versions
    parsed_ethscriptions.select do |eth|
      eth.mimetype == SystemConfigVersion.system_mimetype
    end.map(&:system_config_version).compact
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
    
    BlockBatchContext.get_existing_contract_batch(initial_contracts).each do |contract|
      add_contract(contract)
    end
    
    contract_transactions.each do |contract_tx|
      TransactionContext.set(
        legacy_mode: false,
        call_stack: CallStack.new(TransactionContext),
        gas_counter: GasCounter.new(TransactionContext),
        active_contracts: [],
        current_transaction: contract_tx,
        tx_origin: contract_tx.tx_origin,
        tx_current_transaction_hash: contract_tx.transaction_hash,
        block_number: current_block.block_number,
        block_timestamp: current_block.timestamp,
        block_blockhash: current_block.blockhash,
        block_chainid: current_chainid,
        transaction_index: contract_tx.transaction_index,
        call_counts: {},
        contract_artifacts: {},
        call_log_stack: []
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
    
    artifacts = contract_artifacts.values.select(&:new_record?)
    ContractArtifact.import!(artifacts, on_duplicate_key_ignore: true)
    
    ContractDependency.import!(
      contract_artifacts.values.flat_map(&:contract_dependencies).select(&:new_record?),
      on_duplicate_key_ignore: true
    )
    
    Contract.import!(contracts.select(&:new_record?))
    # TODO do this in batches
    contracts.map do |c|
      c.state_manager.persist(current_block.block_number)
    end
  end
  
  def start_block_passed?
    return unless system_config.start_block_number
    current_block.block_number >= system_config.start_block_number
  end
  
  def add_contract(contract)
    contracts << contract if contract
    contract
  end
  
  def remove_contract(contract)
    contracts.delete(contract)
  end
  
  def get_existing_contract(address)
    in_memory = contracts.detect do |contract|
      contract.deployed_successfully? &&
      contract.address == address
    end
    
    return in_memory if in_memory
    
    from_outer_context = BlockBatchContext.get_existing_contract(address)
    
    add_contract(from_outer_context)
  end
  
  def find_contract_artifact(init_code_hash)
    unless current_block
      return ContractArtifact.
      includes(contract_dependencies: :dependency).
      find_by!(init_code_hash: init_code_hash)
    end
    
    TransactionContext.contract_artifacts[init_code_hash] ||
    contract_artifacts[init_code_hash] ||
    BlockBatchContext.get_contract_artifact!(init_code_hash)
  end
  
  def add_contract_artifact(artifact)
    artifact.block_number = current_block.block_number
    
    contract_artifacts[artifact.init_code_hash] = artifact
  end
  
  def create_new_contract(
    address:,
    init_code_hash:
  )
    artifact = find_contract_artifact(init_code_hash)
    
    contract_class = BlockContext.supported_contract_class(
      init_code_hash
    )
    
    new_contract = Contract.new(
      transaction_hash: current_transaction.transaction_hash,
      block_number: current_block.block_number,
      transaction_index: current_transaction.transaction_index,
      address: address,
      current_type: artifact.name,
      current_init_code_hash: artifact.init_code_hash
    )
    
    add_contract(new_contract)
  end
  
  def supported_contract_class(
    init_code_hash,
    validate: true
  )
    validate_contract_support(init_code_hash) if validate

    find_contract_artifact(init_code_hash).contract_class
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
end
