if ENV.include?('RAILS_ENV') || (defined?(Rails) && Rails.env)
  # Display the RAILS ENV in the prompt
  env = (ENV["RAILS_ENV"] || Rails.env).capitalize.gsub("Development", "Dev").gsub("Production", "Prod")
  
  env_color = if env == "Prod"
    "\e[31m#{env}\e[0m"
  else
    env
  end  
  
  IRB.conf[:PROMPT][:CUSTOM] = {
    :PROMPT_N => "[#{env_color}]> ",
    :PROMPT_I => "[#{env_color}]> ",
    :PROMPT_S => nil,
    :PROMPT_C => "?> ",
    :RETURN => "=> %s\n"
  }
  # Set default prompt
  IRB.conf[:PROMPT_MODE] = :CUSTOM
end

IRB.conf[:USE_AUTOCOMPLETE] = false
