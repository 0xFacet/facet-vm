module ApiCommonParameters
  def self.sort_by_parameter
    {
      name: :sort_by, 
      in: :query, 
      type: :string, 
      description: 'Defines the order of the records to be returned. Can be either "newest_first" (default) or "oldest_first".',
      enum: ['newest_first', 'oldest_first'],
      required: false,
      default: 'newest_first'
    }
  end
  
  def self.reverse_parameter
    {
      name: :reverse,
      in: :query,
      type: :boolean,
      description: 'When set to true, reverses the sort order specified by the `sort_by` parameter.',
      required: false,
      example: "false"
    }
  end

  def self.max_results_parameter
    {
      name: :max_results,
      in: :query,
      type: :integer,
      description: 'Limits the number of results returned. Default value is 25, maximum value is 50.',
      required: false,
      maximum: 50,
      default: 25,
      example: 25
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
