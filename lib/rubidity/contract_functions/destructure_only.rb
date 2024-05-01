class DestructureOnly
  # TODO: make this minimal
  
  include ContractErrors
  
  def initialize(hash)
    @hash = hash
  end

  def to_ary
    if @destructured
      raise InvalidDestructuringError, "This object has already been destructured and cannot be used again"
    else
      @destructured = true
      @hash.values
    end
  end

  def as_json(*)
    @hash.as_json
  end

  def method_missing(name, *args, &block)
    raise InvalidDestructuringError, "This object must be destructured immediately and cannot be used as a regular object"
  end
end
