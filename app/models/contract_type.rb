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

    attr_accessor :contract_type, :address, :caller_address

    def initialize(contract_type:, address:, caller_address:)
      address = TypedVariable.create_or_validate(:address, address).value
    
      self.contract_type = contract_type
      self.address = address
      self.caller_address = caller_address
    end
    
    def contract_proxy
      ContractProxy.create(
        to_contract_address: address,
        to_contract_type: contract_type,
        caller_address: caller_address,
      )
    end
    
    def method_missing(name, *args, **kwargs, &block)
      contract_proxy.send(name, *args, **kwargs, &block)
    end
    
    def respond_to_missing?(name, include_private = false)
      contract_proxy.respond_to?(name, include_private) || super
    end
  end
end
