class Array
  def to_cache_key(namespace = nil)
    ActiveSupport::Cache.expand_cache_key(self, namespace)
  end
end
