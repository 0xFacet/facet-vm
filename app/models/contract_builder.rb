class ContractBuilder < BasicObject
  def self.build_contract_class(
    available_contracts:,
    source:,
    filename:,
    line_number:
  )
    builder = new(available_contracts)
    builder.instance_eval(source, filename, line_number)
  end
  
  def initialize(available_contracts)
    @available_contracts = available_contracts
  end
  
  def contract(name, is: [], abstract: false, &block)
    available_contracts = @available_contracts
    
    implementation_klass = ::Class.new(::ContractImplementation) do
      @parent_contracts = []
      
      ::Array.wrap(is).each do |dep|
        unless parent = available_contracts[dep.name]
          raise "Dependency #{dep} is not available."
        end
        
        @parent_contracts << parent
      end
      
      unless @parent_contracts == @parent_contracts.uniq
        raise "Duplicate parent contracts."
      end
      
      @is_abstract_contract = abstract
      @name = name.to_s
      @available_contracts = available_contracts.merge(@name => self)
      
      instance_eval(&block)
    end
  end
end
