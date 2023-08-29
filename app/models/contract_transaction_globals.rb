class ContractTransactionGlobals
  class Tx
    include ContractErrors

    attr_reader :origin
    
    def origin=(address)
      @origin = TypedVariable.create(:address, address).value
    end
  end
  
  class Block
    include ContractErrors

    attr_accessor :number, :timestamp
    
    def number=(number)
      @number = TypedVariable.create(:uint256, number)
    end
    
    def timestamp=(timestamp)
      @timestamp = TypedVariable.create(:datetime, timestamp)
    end
  end
  
  class Esc
    include ContractErrors

    def initialize(current_transaction)
      @current_transaction = current_transaction
    end
    
    def findEthscriptionById(ethscription_id)
      begin
        as_of = if Rails.env.test?
          "0xb9a22c9f1f6a2c3dd8e0d186b22b13e91db8ec9e2ee2b162f32c5eea15b0f7b5"
        else
          @current_transaction.ethscription.ethscription_id
        end
        
        resp = EthscriptionSync.findEthscriptionById(
          ethscription_id.downcase,
          as_of: 
        )
        
        ethscription_response_to_struct(resp)
      rescue ContractErrors::UnknownEthscriptionError => e
        raise ContractError.new(
          "findEthscriptionById: unknown ethscription: #{ethscription_id}",
          @current_transaction.current_contract
        )
      end
    end
    
    private
    
    def ethscription_response_to_struct(resp)
      params_to_type = {
        ethscriptionId: :ethscriptionId,
        blockNumber: :uint256,
        transactionIndex: :uint256,
        creator: :address,
        currentOwner: :address,
        initialOwner: :address,
        creationTimestamp: :uint256,
        previousOwner: :address,
        contentUri: :string,
        contentSha: :string,
        mimetype: :string
      }
      
      str = Struct.new(*params_to_type.keys)
      
      resp.transform_keys!{|i| i.camelize(:lower).to_sym}
      resp = resp.symbolize_keys
      
      resp[:creationTimestamp] = Time.zone.parse(resp[:creationTimestamp]).to_i

      resp.each do |key, value|
        value_type = params_to_type[key]
        resp[key] = TypedVariable.create(value_type, value)
      end
      
      str.new(*resp.values_at(*params_to_type.keys))
    end
  end
end
