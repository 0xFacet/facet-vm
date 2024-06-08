class ContractBuilder #< UltraBasicObject
  # TODO: does this have to be a basic object?

  def self.build_contract_class(artifact)
    @built_classes ||= {}
    
    dep_classes = artifact.dependencies.map do |dep|
      @built_classes[dep.init_code_hash] ||= build_contract_class(dep)
    end.index_by(&:name).with_indifferent_access
    
    builder = new(artifact, dep_classes)
    
    ::ContractBuilderCleanRoom.execute_user_code_on_context(
      builder,
      [:contract],
      "contract",
      artifact.execution_source_code,
      artifact.name
    )
  end
  
  def initialize(artifact, dependency_classes = {})
    @artifact = artifact
    @dependency_classes = dependency_classes.with_indifferent_access
  end
  
  def contract(name, is: [], abstract: false, upgradeable: false, &block)
    raise ::ContractErrors::ContractBuilderError, "name must be a Symbol" unless name.is_a?(::Symbol)
    raise ::ContractErrors::ContractBuilderError, "is must be an Array" unless is.is_a?(::Array) || is.is_a?(::Symbol)
    raise ::ContractErrors::ContractBuilderError, "abstract must be a Boolean" unless [true, false].include?(abstract)
    raise ::ContractErrors::ContractBuilderError, "upgradeable must be a Boolean" unless [true, false].include?(upgradeable)
    raise ::ContractErrors::ContractBuilderError, "a block must be provided" unless block_given?
    
    name = name.to_s
    artifact = @artifact.dependencies.find { |dep| dep.name == name } || @artifact
    
    unless artifact.name == name
      raise ::ContractErrors::ContractBuilderError, "Contract #{name} not found."
    end
    
    dependency_classes = @dependency_classes
    
    contract_class = ::Class.new(::ContractImplementation) do
      @parent_contracts = []
      
      ::Array.wrap(is).each do |dep|
        unless parent = dependency_classes[dep]
          raise ::ContractErrors::ContractBuilderError, "Dependency #{dep} is not available."
        end
        
        @parent_contracts << parent
      end
      
      @is_upgradeable = upgradeable
      @is_abstract_contract = abstract
      @name = name
      
      ::ContractBuilderCleanRoom.execute_user_code_on_context(
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
    
    contract_class.available_contracts = @dependency_classes.
      merge(name => contract_class).
      deep_dup
    
    # if contract_class.available_contracts.key?(name)
    #   raise ::ContractErrors::ContractBuilderError, "Contract #{name} already exists."
    # end
    
    contract_class.contract_artifact = artifact
    contract_class.init_code_hash = artifact.init_code_hash
    
    contract_class
  end
end
