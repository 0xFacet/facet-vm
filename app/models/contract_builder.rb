class ContractBuilder < BasicObject
  def self.build_contract_class(
    available_contracts:,
    source:,
    filename:,
    line_number: 1
  )
    builder = new(available_contracts)
    new_class = builder.instance_eval(source, filename, line_number)
    
    new_class.tap do |contract_class|
      ast = ::Unparser.parse(source)
      creation_code = ast.inspect
      init_code_hash = ::Digest::Keccak256.hexdigest(creation_code)
      
      contract_class.instance_variable_set(:@source_code, source)
      contract_class.instance_variable_set(:@creation_code, creation_code)
      contract_class.instance_variable_set(:@init_code_hash, init_code_hash)
    end
  end
  
  def initialize(available_contracts)
    @available_contracts = available_contracts
  end
  
  def pragma(...)
  end
  
  def contract(name, is: [], abstract: false, upgradeable: false, &block)
    available_contracts = @available_contracts
    
    implementation_klass = ::Class.new(::ContractImplementation) do
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
      @available_contracts = available_contracts.merge(@name => self)
      
      instance_eval(&block)
    end
  end
end
