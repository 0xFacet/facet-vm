class ContractVariable < GenericVariable
  expose :upgradeImplementation, :currentInitCodeHash, :address
  
  delegate :currentInitCodeHash, :upgradeImplementation, :uncast_address, to: :value
  
  def initialize(...)
    super(...)
  end
  
  def handle_call_from_proxy(method_name, *args, **kwargs)
    # TODO: What if there is a contract function called upgradeImplementation
    
    if method_exposed?(method_name)
      super
    else
      TransactionContext.log_call("TypedVariable", self.class.name, "Contract Call") do
        dynamic_method_handler(method_name, *args, **kwargs)
      end
    end
  end
  
  def dynamic_method_handler(method_name, *args, **kwargs)
    if value.contract_class.public_abi.key?(method_name)
      computed_args = args.presence || kwargs
      
      TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: value.address,
        function: method_name,
        args: computed_args,
        type: :call
      )
    else
      raise ContractError, "Function #{method_name} not exposed in #{self.class.name}"
    end
  end
  
  def as_json
    serialize
  end
  
  def serialize
    value.address
  end
  
  def address
    TypedVariable.create(:address, value.address)
  end
  
  def contract_type
    value.contract_class.name
  end

  def toPackedBytes
    TypedVariable.create(:address, value.address).toPackedBytes
  end

  def eq(other)
    unless other.is_a?(self.class)
      raise ContractError.new("Cannot compare contract with non-contract", self)
    end
    
    other.value.contract_class.init_code_hash == value.contract_class.init_code_hash &&
    other.value.address == value.address
  end
  
  class Value
    include ContractErrors
    
    attr_accessor :contract_class, :address, :uncast_address
    
    def initialize(address:, contract_class:)
      self.uncast_address = address
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.address = address
      self.contract_class = contract_class
    end
    
    def currentInitCodeHash
      TypedVariable.create(:bytes32, contract_class.init_code_hash)
    end
    
    def as_json
      address
    end
    
    def upgradeImplementation(new_init_code_hash, new_source_code)
      typed = TypedVariable.create_or_validate(:bytes32, new_init_code_hash)
      typed_source = TypedVariable.create_or_validate(:string, new_source_code)
      
      artifact_json = begin
        JSON.parse(typed_source.value)
      rescue JSON::ParserError
      end
      
      if artifact_json
        artifact = ContractArtifact.parse_and_store(artifact_json, TransactionContext)
      elsif typed_source.value.present?
        TransactionContext.legacy_mode = true
        artifact = RubidityTranspiler.new(typed_source.value).generate_contract_artifact_json
        
        artifact = ContractArtifact.parse_and_store(artifact, TransactionContext, legacy_mode: true)
      end
      
      new_init_code_hash = typed.value
      
      target = TransactionContext.current_contract
      
      unless address == target.address
        raise ContractError.new("Contracts can only upgrade themselves", target)
      end
      
      begin
        new_implementation_class = BlockContext.supported_contract_class(
          new_init_code_hash,
        )
      rescue UnknownInitCodeHash, ContractSourceNotProvided, Parser::SyntaxError => e
        raise ContractError.new(e.message, target)
      end
      
      current = target.state_manager.get_implementation 
      current_class = BlockContext.supported_contract_class(
        current[:init_code_hash],
        validate: false
      )
      
      unless current_class.is_upgradeable
        raise ContractError.new(
          "Contract is not upgradeable: #{current_class.name}",
          target
        )
      end
      
      unless new_implementation_class
        raise ContractError.new(
          "Implementation not found: #{new_init_code_hash}",
          target
        )
      end
      
      target.state_manager.set_implementation(
        type: new_implementation_class.name,
        init_code_hash: new_init_code_hash
      )
      
      NullVariable.instance
    end
  end
end
