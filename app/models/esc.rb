class Esc
  def initialize(ethscription)
    @ethscription = ethscription
    @as_of = if Rails.env.test?
      "0xf5b2a0296d6be54483955e55c5f921f054e63c6ea6b3b5fc8f686d94f08b97e7"
    else
      if ethscription.mock_for_simulate_transaction
        Ethscription.newest_first.second.ethscription_id
      else
        ethscription.ethscription_id
      end
    end
  end

  def findEthscriptionById(id)
    id = TypedVariable.create_or_validate(:bytes32, id).value

    begin
      Ethscription.esc_findEthscriptionById(id, @as_of)
    rescue ContractErrors::UnknownEthscriptionError => e
      raise ContractError.new(
        "findEthscriptionById: unknown ethscription: #{id}"
      )
    end
  end

  def currentTransactionHash
    TransactionContext.transaction_hash
  end

  def base64Encode(str)
    Base64.strict_encode64(str)
  end
end
