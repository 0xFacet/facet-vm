class User
  def self.user_nonce(user:, current_tx_ethscription_id:)
    scope = Ethscription.where(
      creator: user.downcase
    )
    
    if current_tx_ethscription_id.present?
      scope = scope.where.not(ethscription_id: current_tx_ethscription_id)
    end
    
    scope.count
  end
  
  def self.calculate_contract_address(deployer:, current_tx_ethscription_id:)
    nonce = user_nonce(user: deployer, current_tx_ethscription_id: current_tx_ethscription_id)
    
    rlp_encoded = Eth::Rlp.encode([Integer(deployer, 16), nonce])
  
    hash = Digest::Keccak256.new.hexdigest(rlp_encoded)
  
    contract_address = "0x" + hash[24..-1]
  
    contract_address
  end
end
