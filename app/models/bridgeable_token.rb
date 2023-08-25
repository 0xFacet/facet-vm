class BridgeableToken < Contract
  store_accessor :data,
  :trusted_smart_contract, :pending_withdrawals

  constructor _name: :string,
              _symbol: :string,
              _trusted_smart_contract: :address do |_name, _symbol, _trusted_smart_contract|
    self.trusted_smart_contract = _trusted_smart_contract.downcase

    super(_name, _symbol)
  end

  function :bridge_in, { to: :address, amount: :uint256 }, :public do |to, amount|
    amount = amount.to_i
    to = to.downcase
    
    require(
      env.fetch(:msgSender).downcase == trusted_smart_contract,
      "Only the trusted smart contract can bridge in tokens: #{env.fetch(:msgSender)} != #{trusted_smart_contract}"
    )
    
    _mint(account: to, value: amount)
  end
  
  function :bridge_out, { amount: :uint256 }, :public do |amount|
    amount = amount.to_i
    
    _burn(account: env.fetch(:msgSender).downcase, value: amount)
    self.pending_withdrawals[env.fetch(:msgSender).downcase] += amount
  end
  
  function :mark_withdrawal_complete, { address: :address, amount: :uint256 }, :public do |address, amount|
    amount = amount.to_i
    
    require(
      env.fetch(:msgSender).downcase == trusted_smart_contract,
      'Only the trusted smart contract can mark withdrawals as complete'
    )
    
    require(
      self.pending_withdrawals[address.downcase] >= amount,
      'Insufficient pending withdrawal'
    )
    
    self.pending_withdrawals[address.downcase] -= amount
  end
  
  private
  
  def ensure_default_values
    self.pending_withdrawals ||= {}
    self.pending_withdrawals.default = 0
    
    super
  end
end
