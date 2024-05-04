class ContractBuilder #< BasicObject
  def self.build_contract_class(artifact)
    registry = {}.with_indifferent_access
    
    artifact.dependencies_and_self.each do |dep|
      builder = new(registry)
      
      contract_class = ::CleanRoom.execute_user_code_on_context(
        builder,
        [:contract, :pragma],
        "process_contract_file",
        dep.execution_source_code,
        dep.name,
        1
      )
      
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

  def initialize(available_contracts)
    @available_contracts = available_contracts
  end
  
  def pragma(...)
  end
  
  def contract(name, is: [], abstract: false, upgradeable: false, &block)
    available_contracts = @available_contracts
    
    ::Class.new(::ContractImplementation) do
      @parent_contracts = []
      
      ::Array.wrap(is).each do |dep|
        unless parent = available_contracts[dep]
          # TODO: Raise real exception
          raise "Dependency #{dep} is not available."
        end
        
        @parent_contracts << parent
      end
      
      @is_upgradeable = upgradeable
      @is_abstract_contract = abstract
      @name = name.to_s

      ::CleanRoom.execute_user_code_on_context(
        self,
        [
          :event,
          :function,
          :constructor,
          *::StateVariableDefinitions.public_instance_methods
        ],
        "build_contract_class",
        block
      )
    end
  end
end
