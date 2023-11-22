class ContractBuilder < BasicObject
  def self.build_contract_class(artifact)
    registry = {}.with_indifferent_access
    
    artifact.dependencies_and_self.each do |dep|
      builder = new(registry, dep.source_code, dep.name, 1)
      contract_class = builder.instance_eval_with_isolation
      
      contract_class.instance_variable_set(:@source_code, dep.source_code)
      contract_class.instance_variable_set(:@init_code_hash, dep.init_code_hash)
      registry[dep.name] = contract_class
      
      contract_class.instance_variable_set(
        :@available_contracts,
        registry.deep_dup
      )
    end
    
    registry[artifact.name]
  end

  def instance_eval_with_isolation
    instance_eval(@source, @filename, @line_number).tap do
      remove_instance_variable(:@source)
      remove_instance_variable(:@filename)
      remove_instance_variable(:@line_number)
    end
  end
  
  def initialize(available_contracts, source, filename, line_number)
    @available_contracts = available_contracts
    @source = source
    @filename = filename.to_s
    @line_number = line_number
  end
  
  def pragma(...)
  end
  
  def contract(name, is: [], abstract: false, upgradeable: false, &block)
    available_contracts = @available_contracts
    
    ::Class.new(::ContractImplementation) do
      @parent_contracts = []
      
      ::Array.wrap(is).each do |dep|
        unless parent = available_contracts[dep]
          raise "Dependency #{dep} is not available."
        end
        
        @parent_contracts << parent
      end
      
      @is_upgradeable = upgradeable
      @is_abstract_contract = abstract
      @name = name.to_s
      
      define_singleton_method(:evaluate_block, &block)
      evaluate_block
      singleton_class.remove_method(:evaluate_block)
    end
  end
  
  private
  
  def remove_instance_variable(var)
    ::Object.instance_method(:remove_instance_variable).bind(self).call(var)
  end
end
