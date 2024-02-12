class ContractStateSnapshot
  attr_accessor :state, :type, :init_code_hash
  
  def initialize(state:, type:, init_code_hash:)
    @state = state
    @type = type
    @init_code_hash = init_code_hash
  end
  
  def ==(other)
    self.class == other.class &&
    state.serialize(dup: false) == other.state.serialize(dup: false) &&
    type == other.type &&
    init_code_hash == other.init_code_hash
  end
  
  def serialize(dup: true)
    {
      state: state.serialize(dup: dup),
      type: type,
      init_code_hash: init_code_hash
    }
  end
end
