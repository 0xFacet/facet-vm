class InitCodeMapping < ApplicationRecord
  class << self
    extend Memoist
    
    def old_to_new(old_init_code_hash)
      find_by(old_init_code_hash: old_init_code_hash)&.new_init_code_hash
    end
  end
end
