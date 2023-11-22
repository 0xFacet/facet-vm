module RubidityTypeExtensions
  module StringMethods
    def base64Encode
      Base64.strict_encode64(value)
    end
  end

  module UintOrIntMethods
    def toString
      value.to_s
    end
  end
  
  module AddressMethods
    def call(json_call_data = '{}')
      calldata = JSON.parse(json_call_data)
  
      function = calldata['function']
      args = calldata['args']
      
      data = TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: self,
        function: function,
        args: args,
        type: :call
      ).to_json
      
      DestructureOnly.new( 
        success: true,
        data: TypedVariable.create(:string, data)
      )
    rescue ContractError, TransactionError, JSON::ParserError
      return DestructureOnly.new(
        success: false,
        data: TypedVariable.create(:string)
      )
    end
  end
  
end
