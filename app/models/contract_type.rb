class ContractType < TypedVariable  
  def initialize(type, value, **options)
    super
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

    attr_accessor :contract_type, :address, :uncast_address

    def initialize(contract_type:, address:)
      self.uncast_address = address
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.contract_type = contract_type
      self.address = address
    end
    
    def method_missing(name, *args, **kwargs, &block)
      TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: address,
        to_contract_type: contract_type,
        function: name,
        args: args.presence || kwargs,
        type: :call
      )
    end
    
    def respond_to_missing?(name, include_private = false)
      # It would be annoying to compute this and I don't think we need it
      super
    end
  end
end
