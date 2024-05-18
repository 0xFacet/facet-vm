# TODO: Kill class

class InitCodeMapping < ApplicationRecord
  class << self
    extend Memoist
    
    def cache
      @cache ||= {}
    end
    
    def cached?(old_init_code_hash)
      cache.key?(old_init_code_hash)
    end
    
    def old_to_new(old_init_code_hash)
      raise
      if cache.key?(old_init_code_hash)
        return cache[old_init_code_hash]
      end
      
      candidate = find_by(old_init_code_hash: old_init_code_hash)&.new_init_code_hash
      
      if candidate
        cache[old_init_code_hash] = candidate
      end

      candidate
    end
    
    def cache!(old_init_code_hash, new_init_code_hash)
      return cache[old_init_code_hash] if cached?(old_init_code_hash)
      
      InitCodeMapping.find_or_create_by!(
        old_init_code_hash: old_init_code_hash,
        new_init_code_hash: new_init_code_hash
      )
      
      cache[old_init_code_hash] = new_init_code_hash
    end
  end
end
