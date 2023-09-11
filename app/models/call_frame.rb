class CallFrame
  include ContractErrors
  
  attr_accessor :to_contract_address, :to_contract_type,
    :function_name, :function_args, :to_contract, :type

  def initialize(
    to_contract_address:,
    to_contract_type:,
    function_name:,
    function_args:,
    type:
  )
    @to_contract_address = to_contract_address
    @to_contract_type = to_contract_type
    @function_name = function_name
    @function_args = function_args
    @type = type
  end
  
  def set_contract!
    self.to_contract = create_or_find_to_contract
    
    validate_to_contract!
    validate_function!
    
    self.function_name = :constructor if type == :create
    
    to_contract
  end
  
  def create_or_find_to_contract
    return create_contract! if type == :create
    
    Contract.find_by(address: to_contract_address)
  end
  
  def create_contract!
    validate_contract_creation!
    
    Contract.create!(
      transaction_hash: TransactionContext.transaction_hash,
      address: calculate_msg_sender_contract_address,
      type: to_contract_type,
    ).tap do |c|
      TransactionContext.current_transaction.created_contract_address = c.address
    end
  end
  
  def validate_to_contract!
    if to_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if to_contract_type && !to_contract.implements?(to_contract_type.to_s)
      raise ContractError.new("Contract doesn't implement interface: #{to_contract_address}, #{to_contract_type}", to_contract)
    end
  end
  
  def persist_state?
    function_object.read_only?
  end
  
  def function_object
    public_abi = to_contract.implementation.public_abi
    
    public_abi[function_name]
  end
  
  def validate_function!
    function = function_object

    if !function && type != :create
      raise ContractError.new("Call to unknown function #{function_name}", to_contract)
    end
    
    if type == :static_call && !function.read_only?
      raise ContractError.new("Cannot call non-read-only function in static call: #{function_name}", to_contract)
    end
    
    if type != :create && function.constructor?
      raise ContractError.new("Cannot call constructor function: #{function_name}", to_contract)
    end
    
    if type == :create && function_name.present?
      raise ContractError.new("Cannot call function on contract creation", to_contract)
    end
  end
  
  def calculate_msg_sender_contract_address
    deployer = TransactionContext.msg_sender.serialize
    
    scope = ContractTransaction.where(
      from_address: deployer
    ).where.not(transaction_hash: TransactionContext.transaction_hash)
    
    nonce = scope.count
    
    rlp_encoded = Eth::Rlp.encode([Integer(deployer, 16), nonce])
  
    hash = Digest::Keccak256.new.hexdigest(rlp_encoded)
  
    "0x" + hash[24..-1]
  end
  
  def validate_contract_creation!
    unless Contract.valid_contract_types.include?(to_contract_type.to_sym)
      raise TransactionError.new("Invalid contract type: #{to_contract_type}")
    end
    
    implementation_class = "Contracts::#{to_contract_type}".constantize
    
    if implementation_class.is_abstract_contract
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_type}")
    end
  end
end
