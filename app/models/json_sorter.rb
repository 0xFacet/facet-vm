module JsonSorter
  def self.sort_hash(hash)
    sorted = hash.sort_by { |k, _| [k.length, k] }
    
    sorted.each_with_object({}) do |(key, value), result|
      result[key] = value.is_a?(Hash) ? sort_hash(value) : value
    end
  end
end
