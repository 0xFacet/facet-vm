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
      @number = TypedVariable.create(:uint256, number).value
    end
    
    def timestamp=(timestamp)
      @timestamp = TypedVariable.create(:uint256, timestamp).value
    end
  end
  
  class Esc
    include ContractErrors

    def initialize(current_transaction)
      @current_transaction = current_transaction
    end
    
    def findEthscriptionById(ethscription_id)
      begin
        EthscriptionSync.findEthscriptionById(
          ethscription_id.downcase,
          as_of: @current_transaction.ethscription.ethscription_id
        )
      rescue ContractErrors::UnknownEthscriptionError => e
        raise ContractError.new(
          "findEthscriptionById: unknown ethscription: #{ethscription_id}",
          @current_transaction.current_contract
        )
      end
    end
  end
end
