class ContractStateSnapshot
  attr_accessor :state, :type, :init_code_hash
  
  def initialize(state:, type:, init_code_hash:)
    @state = state
    @type = type
    @init_code_hash = init_code_hash
  end
  
  def ==(other)
    self.class == other.class &&
    state == other.state &&
    type == other.type &&
    init_code_hash == other.init_code_hash
  end
end
