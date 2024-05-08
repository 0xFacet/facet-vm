class ParsedContract
  class InvalidParsedContract < StandardError; end
  extend Memoist
  extend RuboCop::AST::NodePattern::Macros
  attr_accessor :name, :parents, :abstract, :upgradeable, :body,
    :available_contracts
  
  # TODO: case with no explicit visibility
    
  def_node_matcher :state_variable_definition?, <<~PATTERN
    (send nil? $#state_variable_name? (sym $_) (sym $_)?)
  PATTERN
  
  def state_variable_name?(name)
    StateVariableDefinitions.instance_methods.include?(name)
  end
  
  def_node_matcher :struct_state_variable_definition?, <<~PATTERN
    (send nil? $#struct_name? (sym $_) (sym $_)?)
  PATTERN
  
  def struct_name?(name)
    calculated_struct_definitions.any?{|i| i.name.to_sym == name.to_sym }
  end
  
  def_node_matcher :mapping_call, <<~PATTERN
    (send nil? :mapping 
      (begin $(hash ...))  # Captures the hash inside a begin block
      (sym $_visibility) 
      (sym $_name))
  PATTERN
  
  def_node_matcher :struct_definition, <<~PATTERN
    (block 
      (send nil? :struct 
        (sym $_struct_name)) 
      (args)
      $(begin 
        (send nil? $_field_type (sym $_field_name))+))
  PATTERN
  
  # def_node_matcher :event_definition, <<~PATTERN
  #   (send nil? :event 
  #     (sym $_event_name) 
  #     (hash 
  #       $(pair (sym _key) (sym _value))+)
  #   )
  # PATTERN
  
  def_node_matcher :event_definition, <<~PATTERN
    (send nil? :event 
      (sym $_event_name) 
      $(hash ...)
    )
  PATTERN
  
  def_node_matcher :array_variable_declaration, <<~PATTERN
    (send nil? :array 
      (sym $_type) 
      (sym $_visibility) 
      (sym $_name)
      $(hash (pair (sym :initial_length) (int _)))?)
  PATTERN
  
  def_node_matcher :inner_mapping, <<~PATTERN
    (send nil? :mapping 
      $(hash ...)
    )
  PATTERN
  
  def_node_matcher :contract_function?, <<~PATTERN
    (block
      (send nil? :function $_name $...)
      (args)
      $_body?
    )
  PATTERN
  
  def_node_matcher :contract_function_no_body?, <<~PATTERN
    (send nil? :function $_name $...)
  PATTERN
  
  def_node_matcher :constructor?, <<~PATTERN
    (block
      (send nil? :constructor $...)
      (args)
      $_body?
    )
  PATTERN
  
  def initialize(name:, parents:, abstract:, upgradeable:, body:, available_contracts:)
    self.name = name
    self.parents = parents
    self.abstract = abstract
    self.upgradeable = upgradeable
    self.body = body
    self.available_contracts = available_contracts
  end
  
  def process!
    body.children.each do |node|
      # ap node
      valid = contract_function?(node) ||
        contract_function_no_body?(node) ||
        constructor?(node) ||
        mapping_call(node) ||
        struct_definition(node) ||
        array_variable_declaration(node) ||
        event_definition(node) ||
        state_variable_definition?(node) ||
        struct_state_variable_definition?(node)
        
      unless valid
        puts body.unparse rescue body
        raise InvalidParsedContract, "Invalid node: #{node.inspect}"
      end
    end
    
    functions.each(&:process!)
  end
  memoize :process!
  
  def parse_function_details(node)
    contract_function?(node) do |name, args, body|
      args = args.flatten
      details = {
        contract: self,
        name: name.value,
        arguments: {},
        visibility: nil,
        state_mutation: nil,
        return_type: nil,
        body: body.first || s(:begin),
        original_node: node.deep_dup
      }
      
      args.each.with_index do |arg, idx|
        case arg.type
        when :sym
          details[:visibility] = arg.value if [:public, :private, :protected].include?(arg.value)
          details[:state_mutation] = arg.value if [:view, :pure, :payable].include?(arg.value)
        when :hash
          arg.pairs.each do |pair|
            key, value = pair.key.children.first, pair.value.children.first
            
            if key == :returns && idx = args.length - 1
              # ap pair
              # if value.is_a?(RuboCop::AST::PairNode)
              #   kids = value.children
                
              #   if kids[1].type == :array
              #     value = [kids[0].value]
              #   else
              #     value = [value.children.map(&:value)].to_h
              #   end
              # end
              
              # binding.pry if value.is_a?(RuboCop::AST::Node)
              
              details[:return_type] = value
            elsif idx == 0
              details[:arguments][key] = value
            end
          end
        end
      end
  
      ParsedContractFunction.new(**details)
    end
  end
  memoize :parse_function_details
  
  def functions
    body.children.each.with_object([]) do |node, functions|
      contract_function?(node) do |name, args, body|
        functions << parse_function_details(node)
      end
    end
  end
  memoize :functions
  
  def calculated_state_variables
    if parent_contracts.empty?
      return state_variables
    end
    
    state_variables + parent_contracts.flat_map(&:calculated_state_variables)
  end
  memoize :calculated_state_variables
  
  def calculated_functions
    if parent_contracts.empty?
      return functions
    end
    
    functions + parent_contracts.flat_map(&:calculated_functions)
  end
  memoize :calculated_functions
  
  def parent_contracts
    parents.map{|i| available_contracts.find{|j| j.name == i}}
  end
  memoize :parent_contracts
  
  def calculated_parent_contracts
    parent_contracts.map do |contract|
      contract.parent_contracts + [contract]
    end.flatten.uniq
  end
  memoize :calculated_parent_contracts
  
  def calculated_available_contracts
    [self] + available_contracts
  end
  
  def struct_definitions
    body.children.each.with_object([]) do |node, struct_definitions|
      struct_definition(node) do |struct_name, fields, field_types, field_values|
        field_hash = field_values.zip(field_types).to_h
        
        struct_definitions << OpenStruct.new(
          name: struct_name,
          type: :struct,
          fields: field_hash
        )
      end
    end
  end
  memoize :struct_definitions
  
  def calculated_struct_definitions
    struct_definitions + parent_contracts.flat_map(&:calculated_struct_definitions)
  end
  memoize :calculated_struct_definitions
  
  def state_variables
    body.children.each.with_object([]) do |node, state_vars|
      state_variable_definition?(node) do |var_type, visibility, var_name|
        var_name = var_name.first if var_name.is_a?(Array)
        
        if var_name.blank?
          var_name = visibility
          visibility = :internal
        end
        
        state_vars << OpenStruct.new(
          type: var_type,
          visibility: visibility,
          name: var_name,
        )
      end
  
      mapping_call(node) do |hash, visibility, name|
        state_vars << OpenStruct.new(
          name: name,
          visibility: visibility,
          type: :mapping,  # Indicate the type as mapping
          mapping: process_mapping_hash(hash),
        )
      end
      
      array_variable_declaration(node) do |type, visibility, name, initial_length|
        state_vars << OpenStruct.new(
          name: name,
          visibility: visibility,
          type: :array,
          value_type: type
        )
      end
      
      struct_state_variable_definition?(node) do |struct_name, visibility, var_name|
        var_name = var_name.first if var_name.is_a?(Array)
        
        state_vars << OpenStruct.new(
          name: var_name,
          visibility: visibility,
          type: :struct,
          struct_name: struct_name
        )
      end
    end
  end
  memoize :state_variables
  
  def process_mapping_hash(node)
    return {} unless node.type == :hash
    result = {}
    
    node.pairs.each do |pair|
      key, value = pair.key, pair.value
      key_name = key.value
      
      if inner_mapping(value)
        inner_mapping(value) do |inner_hash|
          result[key_name] = {
            mapping: process_mapping_hash(inner_hash)
          }
        end
      else
        result[key_name] = value.children.first
      end
    end
  
    result
  end
  memoize :process_mapping_hash
  
  private
  
  def s(type, *children)
    RuboCop::AST::Node.new(type, children)
  end
end
