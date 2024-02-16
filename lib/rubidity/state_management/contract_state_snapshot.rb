class ContractStateSnapshot
  attr_accessor :state, :type, :init_code_hash
  
  def initialize(state:, type:, init_code_hash:)
    @state = state
    @type = type
    @init_code_hash = init_code_hash
    @memoized_serialized_state = nil
  end
  
  def ==(other)
    self.class == other.class &&
    serialized_state == other.serialized_state &&
    type == other.type &&
    init_code_hash == other.init_code_hash
  end
  
  def serialize(dup: true)
    @serialized ||= {}
    # Check if a non-duped version is requested and a duped version exists
    return @serialized[true] if !dup && @serialized.key?(true)
    return @serialized[dup] if @serialized.key?(dup)
  
    @serialized[dup] = {
      state: state.serialize(dup: dup),
      type: type,
      init_code_hash: init_code_hash
    }
  end

  def serialized_state
    @memoized_serialized_state ||= state.serialize(dup: false)
  end
end
