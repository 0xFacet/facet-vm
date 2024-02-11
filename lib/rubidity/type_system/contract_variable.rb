class ContractVariable < TypedVariable  
  def initialize(...)
    super(...)
  end
  
  def serialize
    value.address
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

  class Value
    include ContractErrors
    extend AttrPublicReadPrivateWrite
    
    attr_public_read_private_write :contract_class, :address, :uncast_address

    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.contract_class.init_code_hash == contract_class.init_code_hash &&
      other.address == address
    end
    
    def initialize(address:, contract_class:)
      self.uncast_address = address
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.address = address
      self.contract_class = contract_class
    end
    
    def method_missing(name, *args, **kwargs, &block)
      computed_args = args.presence || kwargs
      
      super unless contract_class
      
      known_function = contract_class.public_abi[name]
      
      unless known_function && known_function.args.length == computed_args.length
        raise ContractError.new("Contract doesn't implement interface: #{contract_class.name}, #{name}")
      end
      
      TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: address,
        function: name,
        args: computed_args,
        type: :call
      )
    end
    
    def respond_to_missing?(name, include_private = false)
      !!contract_class.public_abi[name] || super
    end
    
    def contract_type
      contract_class.name
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
      rescue UnknownInitCodeHash, Parser::SyntaxError => e
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
      
      nil
    end
  end
end
