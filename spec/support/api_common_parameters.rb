module ApiCommonParameters
  def self.reverse_parameter
    {
      name: :reverse,
      in: :query,
      type: :boolean,
      description: 'When set to true, reverses the sort order specified by the sort_by parameter.',
      required: false
    }
  end

  def self.max_results_parameter
    {
      name: :max_results,
      in: :query,
      type: :integer,
      description: 'Limits the number of results returned. Maximum and default value is 50.',
      required: false,
      maximum: 50,
      default: 25
    }
  end

  def self.page_key_parameter
    {
      name: :page_key,
      in: :query,
      type: :string,
      description: 'Pagination key from the previous response. Used for fetching the next set of results.',
      required: false
    }
  end
end
