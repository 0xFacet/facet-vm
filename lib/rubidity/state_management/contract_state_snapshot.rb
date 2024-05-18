class ContractStateSnapshot
  attr_accessor :type, :init_code_hash
  
  def initialize(type:, init_code_hash:)
    @type = type
    @init_code_hash = init_code_hash
  end
  
  def ==(other)
    self.class == other.class &&
    type == other.type &&
    init_code_hash == other.init_code_hash
  end
end
