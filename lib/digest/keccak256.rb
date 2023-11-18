module Digest::Keccak256
  class << self
    extend Memoist

    def hexdigest(input)
      Eth::Util.bin_to_hex(bindigest(input))
    end
    memoize :hexdigest
    
    def bindigest(input)
      Eth::Util.keccak256(input)
    end
    memoize :bindigest
  end
end
