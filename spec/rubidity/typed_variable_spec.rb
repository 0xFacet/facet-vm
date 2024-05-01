# spec/models/typed_variable_spec.rb
require 'rails_helper'

RSpec.describe TypedVariable, type: :model do
  class TypedVariable
    def ft
      if self.is_a?(::TypedVariable) && self.type.bool?
        self.value
      elsif [true, false].include?(val)
        val
      else
        binding.pry
        raise "Invalid boolean value"
      end
    end
  end
  
  describe '.create_or_validate' do
    it 'returns the same TypedVariable if the value is a TypedVariable and its type can be assigned from the specified type' do
      typed_variable = TypedVariable.create(:uint256, 1)
      expect(TypedVariable.create_or_validate(:uint256, typed_variable).eq(typed_variable).value).to eq(true)
    end

    it 'is fine to go up in bits' do
      typed_variable = TypedVariable.create(:uint128, 1)
      expect(TypedVariable.create_or_validate(:uint256, typed_variable)).to be_a(TypedObject)
    end

    it 'creates a new TypedVariable if the value is not a TypedVariable' do
      expect(TypedVariable.create_or_validate(:uint256, 1)).to be_a TypedObject
    end
    
    it 'raises a VariableTypeError if the value is a TypedVariable and its type cannot be assigned from the specified type' do
      typed_variable = TypedVariable.create(:uint256, 2**128) # This value is too large for uint128
      expect { TypedVariable.create_or_validate(:uint128, typed_variable) }.to raise_error(ContractErrors::VariableTypeError)
    end
    
    it "handles bools correctly" do
      false_bool = TypedVariable.create_or_validate(:bool, false)
      true_bool = TypedVariable.create_or_validate(:bool, true)

      int = TypedVariable.create_or_validate(:uint256, 10)
      
      mapping_type = Type.create(:mapping, key_type: :uint256, value_type: :bool)
      mapping = TypedVariable.create_or_validate(mapping_type, {})
      
      expect(false_bool).to be_a(TypedVariable)
      expect(false_bool).to be_a(TypedVariable)
      expect(false_bool.type.name).to eq(:bool)
      
      expect { false_bool.eq(int) }.to raise_error(/Cannot compare bool with uint256/)
      
      expect(false_bool.not.value).to eq(true)
      expect(false_bool.not.eq(true_bool).value).to eq(true)
      expect { false_bool == false }.to raise_error(TypeError, "Call eq() instead of ==()")
      expect(true_bool).to be_a(TypedVariable)
      
      expect { true_bool == int }.to raise_error(TypeError, "Call eq() instead of ==()")
      
      expect(true_bool.not.value).to eq(false)
      
      expect { true_bool == true }.to raise_error(TypeError, "Call eq() instead of ==()")

      
      expect(mapping[1].eq(false_bool).value).to eq(true)
      expect(mapping.[]=(1, true).eq(true_bool).value).to eq(true)
      expect(mapping[1].eq(true_bool).value).to eq(true)
      expect(mapping.serialize).to eq({"1"=>true})
      
      expect { TypedVariable.new(Type.create(:bool)) }.to_not raise_error
      expect { false_bool.value = 4 }.to raise_error(TypeError)
      expect { !int }.to raise_error("Call not() instead of !")
      expect { int.not }.to raise_error("Cannot negate #{int.inspect}")
    end
  end
  
  it 'handles mappings' do
    mapping_type1 = Type.create(:mapping, key_type: :string, value_type: :bool)
    mapping_type2 = Type.create(:mapping, key_type: :uint256, value_type: mapping_type1)
    mapping = TypedVariable.create_or_validate(mapping_type2, {})
    
    expect(mapping[1]['hi'].ft).to eq(false)
    
    expect(mapping[1].[]=('hi', true).ft).to eq(true)
    expect(mapping[1]['hi'].ft).to eq(true)
    expect(mapping[1]['bye'].ft).to eq(false)
    
    expect(mapping[1].[]=('bye', true).ft).to eq(true)
    
    expect(mapping[1]['bye'].ft).to eq(true)
    expect(mapping[1]['hi'].ft).to eq(true)
    expect(mapping[1]['a'].ft).to eq(false)
    
    len = TypedVariable.create(:uint256, 10).to_proxy
    
    
    m_ary_type = ContractImplementation.mapping ({ uint256: ContractImplementation.array(:string, initial_length: len) })
    map_array = TypedVariable.create_or_validate(Type.create(:mapping, key_type: :uint256, value_type: m_ary_type))
    
    expect(map_array[1][1][1].eq(TypedVariable.create(:string)).value).to eq(true)
  end
end
