module Digest::Keccak256
  def self.hexdigest(input)
    Eth::Util.bin_to_hex(bindigest(input))
  end
  
  def self.bindigest(input)
    Eth::Util.keccak256(input)
  end
end
