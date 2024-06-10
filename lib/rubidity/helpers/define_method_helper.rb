module DefineMethodHelper
  class MethodAlreadyDefinedError < StandardError
    def initialize(method_name)
      super("Method #{method_name} is already defined")
    end
  end
  
  def self.included(base)
    base.extend(ClassMethods)
    base.include(SingletonMethodProtection)
    # base.singleton_class.prepend(SingletonMethodProtection)
    # base.prepend(InstanceMethodProtection)
  end

  module ClassMethods
    def define_method_with_check(method_name, &block)
      DefineMethodHelper.raise_if_method_defined(self, method_name)
      define_method(method_name, &block)
    end
  end

  module SingletonMethodProtection
    # def singleton_method_added(method_name)
    #   DefineMethodHelper.raise_if_method_defined(singleton_class, method_name)
    #   super
    # end

    def define_singleton_method_with_check(method_name, &block)
      singleton_class = (class << self; self; end)
      DefineMethodHelper.raise_if_method_defined(singleton_class, method_name)
      
      singleton_class.send(:define_method, method_name, &block)
      
      # define_singleton_method(method_name, &block)
    end
  end

  module InstanceMethodProtection
    # def method_added(method_name)
    #   DefineMethodHelper.raise_if_method_defined(self.class, method_name)
    #   super
    # end
  end

  def self.raise_if_method_defined(klass, method_name)
    if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
      raise MethodAlreadyDefinedError.new(method_name)
    end
  end
end
