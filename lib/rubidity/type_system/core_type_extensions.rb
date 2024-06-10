module CoreTypeExtensions
  module Etherable
    def ether
      (self.to_d * 1e18.to_d).to_i
    end
  end
  
  ::Integer.include Etherable
  ::Float.include Etherable
end
