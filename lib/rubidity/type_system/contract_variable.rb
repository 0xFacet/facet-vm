class ContractVariable < GenericVariable  
  delegate :currentInitCodeHash, :upgradeImplementation, to: :value
  
  def initialize(...)
    super(...)
    
    value.contract_class.public_abi.each_key do |method_name|
      define_singleton_method(method_name) do |*args, **kwargs|
        computed_args = VM.deep_unbox(args.presence || kwargs)
        
        TransactionContext.call_stack.execute_in_new_frame(
          to_contract_address: value.address,
          function: method_name,
          args: computed_args,
          type: :call
        )
      end
    end
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
  
  def method_missing(name, *args, **kwargs, &block)
    value.send(name, *args, **kwargs, &block)
  end
  
  def respond_to_missing?(name, include_private = false)
    value.respond_to?(name, include_private) || super
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
    extend AttrPublicReadPrivateWrite
    
    attr_public_read_private_write :contract_class, :address, :uncast_address
    
    def initialize(address:, contract_class:)
      self.uncast_address = address
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.address = address
      self.contract_class = contract_class
    end
    
    def currentInitCodeHash
      TypedVariable.create(:bytes32, contract_class.init_code_hash)
    end
    
    def upgradeImplementation(new_init_code_hash, new_source_code)
      typed = TypedVariable.create_or_validate(:bytes32, new_init_code_hash)
      typed_source = TypedVariable.create_or_validate(:string, new_source_code)
      
      new_init_code_hash = typed.value
      
      target = TransactionContext.current_contract
      
      unless address == target.address
        raise ContractError.new("Contracts can only upgrade themselves", target)
      end
      
      begin
        new_implementation_class = BlockContext.supported_contract_class(
          new_init_code_hash,
          typed_source.value.presence
        )
      rescue UnknownInitCodeHash, ContractSourceNotProvided, Parser::SyntaxError => e
        raise ContractError.new(e.message, target)
      end
      
      unless target.implementation_class.is_upgradeable
        raise ContractError.new(
          "Contract is not upgradeable: #{target.implementation_class.name}",
          target
        )
      end
      
      unless new_implementation_class
        raise ContractError.new(
          "Implementation not found: #{new_init_code_hash}",
          target
        )
      end
      
      target.assign_attributes(
        current_type: new_implementation_class.name,
        current_init_code_hash: new_init_code_hash
      )
      
      NullVariable.instance
    end
  end
end
