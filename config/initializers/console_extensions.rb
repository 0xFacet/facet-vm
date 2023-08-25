def no_ar_logging
  ActiveRecord::Base::logger.level = 1
end
