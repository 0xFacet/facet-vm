class CacheVersion < ApplicationRecord
  def self.version
    CacheVersion.pluck(:version).last
  end
  
  def self.increment
    Rails.cache.clear
    increment_counter(:version, 1)
  end
end
