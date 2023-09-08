class ContractTransactionGlobals
  class Message
    attr_reader :sender
    
    def sender=(address)
      @sender = TypedVariable.create(:address, address)
    end
  end
  
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
    
    def initialize(current_transaction)
      @current_transaction = current_transaction
    end
    
    def blockhash(block_number)
      unless @current_transaction.ethscription.block_number == block_number.value # TODO FIX
        raise "Not implemented"
      end
      
      @current_transaction.ethscription.block_blockhash
    end
    
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
      ethscription_id = TypedVariable.create_or_validate(:ethscriptionId, ethscription_id).value
      
      begin
        as_of = if Rails.env.test?
          "0xc59f53896133b7eee71167f6dbf470bad27e0af2443d06c2dfdef604a6ddf13c"
        else
          if @current_transaction.ethscription.mock_for_simulate_transaction
            Ethscription.newest_first.second.ethscription_id
          else
            @current_transaction.ethscription.ethscription_id
          end
        end
        
        resp = EthscriptionSync.findEthscriptionById(
          ethscription_id.downcase,
          as_of: as_of
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
        blockBlockhash: :string,
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
