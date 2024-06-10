module Exposable
  extend ActiveSupport::Concern
  
  included do
    @exposed_methods = Set.new
  end
  
  def method_exposed?(name)
    exposed_methods.include?(name.to_sym)
  end
  
  def exposed_methods
    # self.class.__send__(:validate_exposed_methods)
    # VM.call_method(self, :class).exposed_methods + exposed_instance_methods
    self.class.exposed_methods + exposed_instance_methods
  end
  
  def exposed_instance_methods
    @exposed_instance_methods ||= Set.new
  end
  
  def expose_instance_method(*names)
    exposed_instance_methods.merge(names.map(&:to_sym))
    validate_exposed_instance_methods
  end
  
  private
  
  def validate_exposed_instance_methods
    # exposed_instance_methods.each do |name|
    #   unless public_methods.include?(name)
    #     raise NameError, "undefined method `#{name}' for instance of `#{self.class.name}'"
    #   end
    # end
  end
  
  class_methods do
    def wrap_with_logging(*method_names)
      method_names.each do |method_name|
        alias_method "original_#{method_name}", method_name
  
        define_method(method_name) do |*args, **kwargs, &block|
          TransactionContext.log_call(self.class.name, method_name) do
            send("original_#{method_name}", *args, **kwargs, &block)
          end
        end
      end
    end
    
    def expose(*names)
      names = names.map(&:to_sym)
      
      exposed_methods.merge(names)
    end

    def exposed_methods
      @exposed_methods
    end

    def inherited(subclass)
      super
      
      inherited_exposure = exposed_methods - subclass.instance_methods(false)
      
      subclass.instance_variable_set(:@exposed_methods, inherited_exposure)
    end
    
    private
    
    # def validate_exposed_methods
    #   @exposed_methods.each do |name|
    #     unless public_method_defined?(name)
    #       raise NameError, "undefined method `#{name}' for class `#{self.name}'"
    #     end
    #   end
    # end
  end
end
