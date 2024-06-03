class AddressVariable < GenericVariable
  expose :call
  
  def initialize(...)
    super(...)
  end
  
  def call(json_call_data = nil, **kwargs)
    calldata = kwargs.presence || JSON.parse(json_call_data.value)
    
    function, args = if calldata.is_a?(Hash)
      calldata = calldata.with_indifferent_access
      
      [calldata['function'], calldata['args']]
    elsif calldata.is_a?(Array)
      [calldata.first, calldata.drop(1)]
    end
    
    data = TransactionContext.call_stack.execute_in_new_frame(
      call_level: :low,
      to_contract_address: self,
      function: function,
      args: args,
      type: :call
    ).to_json
    
    DestructureOnly.new( 
      success: TypedVariable.create(:bool, true),
      data: TypedVariable.create(:string, data)
    )
  rescue ContractError, TransactionError, JSON::ParserError => e
    return DestructureOnly.new(
      success: TypedVariable.create(:bool, false),
      data: TypedVariable.create(:string)
    )
  end
  wrap_with_logging :call
end
