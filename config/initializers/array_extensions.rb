class Array
  def to_cache_key(*namespace)
    namespace = namespace.present? ? namespace.to_cache_key : nil
    raw_key = ActiveSupport::Cache.expand_cache_key(self, namespace)
    
    raw_key.length > 250 ? Digest::SHA256.hexdigest(raw_key) : raw_key
  end
end
