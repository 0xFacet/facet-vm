if Rails.env.development?
  ActiveRecordQueryTrace.enabled = false
  ActiveRecordQueryTrace.ignore_cached_queries = true # Default is false.
  ActiveRecordQueryTrace.colorize = :light_purple   # Colorize in specific color
end
