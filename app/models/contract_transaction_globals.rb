class ContractTransactionGlobals
  class Tx
    attr_reader :origin
    
    def origin=(address)
      @origin = TypedVariable.create(:address, address).value
    end
  end
  
  class Block
    attr_accessor :number, :timestamp
    
    def number=(number)
      @number = TypedVariable.create(:uint256, number).value
    end
    
    def timestamp=(timestamp)
      @timestamp = TypedVariable.create(:uint256, timestamp).value
    end
  end
end
