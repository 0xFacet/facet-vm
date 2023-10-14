class ContractBuilder < BasicObject
  def initialize(available_contracts)
    @available_contracts = available_contracts.dup
  end
  
  def contract(name, is: [], abstract: false, &block)
    available_contracts = @available_contracts
    
    implementation_klass = ::Class.new(::ContractImplementation) do
      ::Array.wrap(is).each do |dep|
        unless dep_obj = available_contracts[dep.name]
          raise "Dependency #{dep} is not available."
        end
        
        self.parent_contracts << dep_obj
      end
      self.parent_contracts = self.parent_contracts.uniq
      
      if abstract
        @is_abstract_contract = true
      end
      
      define_singleton_method(:name) do
        name.to_s
      end
    end
    
    implementation_klass.tap do |contract|
      contract.instance_variable_set(
        :@available_contracts,
        @available_contracts.merge(name => contract)
      )
      
      contract.instance_eval(&block)
    end
  end
end
