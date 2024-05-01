class CleanRoomAdmin < UltraBasicObject
  def self.call_method(
    method_name:,
    binding:,
    args: [],
    kwargs: {},
    &block
  )
  ::Object.instance_method(method_name).
    bind(binding).call(*::Array.wrap(args), **kwargs, &block)
  end
  
  def self.call_inspect(binding)
    ::CleanRoomAdmin.call_method(
      method_name: :inspect,
      binding: binding
    )
  end
  
  def self.get_instance_variable(binding, name)
    unless name.starts_with?("@")
      name = "@#{name}"
    end
    
    defined = ::CleanRoomAdmin.call_method(
      method_name: :instance_variable_defined?,
      binding: binding,
      args: name
    )
    
    unless defined
      raise "Instance variable not defined: #{name}"
    end
    
    ::CleanRoomAdmin.call_method(
      method_name: :instance_variable_get,
      binding: binding,
      args: name
    )
  end
  
  def self.call_is_a?(binding, name)
    ::CleanRoomAdmin.call_method(
      method_name: :is_a?,
      binding: binding,
      args: name
    )
  end
  
  # def self.set_instance_variable(binding, name, value)
  #   ::CleanRoomAdmin.call_method(
  #     method_name: :instance_variable_set,
  #     binding: binding,
  #     args: name,
  #     kwargs: value
  #   )
  # end
end

