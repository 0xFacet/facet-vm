class ContractFunctionArgs
  include Exposable
  
  def initialize(args = {})
    args.each do |key, value|
      define_singleton_method(key) { value }
      expose_instance_method(key)
    end
  end
end
