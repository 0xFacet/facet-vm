class ContractType < TypedVariable  
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

  class Proxy
    include ContractErrors
    extend AttrPublicReadPrivateWrite
    
    attr_public_read_private_write :contract_type, :address,
      :uncast_address, :contract_interface

    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.contract_type == contract_type &&
      other.address == address
    end
    
    def initialize(contract_type:, address:, contract_interface:)
      self.uncast_address = address
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.contract_type = contract_type
      self.address = address
      self.contract_interface = contract_interface
    end
    
    def method_missing(name, *args, **kwargs, &block)
      computed_args = args.presence || kwargs
      
      super unless contract_interface
      
      known_function = contract_interface.public_abi[name]
      
      unless known_function && known_function.args.length == computed_args.length
        raise ContractError.new("Contract doesn't implement interface: #{contract_type}, #{name}")
      end
      
      TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: address,
        function: name,
        args: computed_args,
        type: :call
      )
    end
    
    def respond_to_missing?(name, include_private = false)
      !!contract_interface.public_abi[name] || super
    end    
  end
end
