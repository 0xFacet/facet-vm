class UltraBasicObject < BasicObject
  (instance_methods + private_instance_methods).each do |method_name|
    unless [:__send__, :initialize, :singleton_method_added].include?(method_name)
      undef_method(method_name)
    end
  end
end
