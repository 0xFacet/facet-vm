# spec/models/typed_variable_spec.rb
require 'rails_helper'

RSpec.describe TypedVariable, type: :model do
  describe '.create_or_validate' do
    it 'returns the same TypedVariable if the value is a TypedVariable and its type can be assigned from the specified type' do
      typed_variable = TypedVariable.create(:uint256, 1)
      expect(TypedVariable.create_or_validate(:uint256, typed_variable)).to eq typed_variable
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
      
      expect(false_bool).to be_a(FalseClass)
      expect(false_bool).to be_a(TypedObject)
      expect(false_bool.type.name).to eq(:bool)
      expect(false_bool).not_to be_a(TypedVariable)
      
      expect(false_bool == int).to eq(false)
      expect(!false_bool).to eq(true)
      expect(!false_bool).to eq(true_bool)
      expect(false_bool == false).to eq(true)

      expect(true_bool).to be_a(TrueClass)
      expect(true_bool).to be_a(TypedObject)
      expect(true_bool).not_to be_a(TypedVariable)
      
      expect(true_bool == int).to eq(false)
      expect(!true_bool).to eq(false)
      expect(true_bool == true).to eq(true)
      
      expect(mapping[1]).to eq(false)
      expect(mapping[1] = true).to eq(true)
      expect(mapping[1]).to eq(true)
      expect(mapping.serialize).to eq({"1"=>true})
      
      expect { TypedVariable.new(Type.create(:bool)) }.to raise_error(TypeError)
      expect { false_bool.value = 4 }.to raise_error(TypeError)
      expect { !int }.to raise_error(TypeError)
    end
  end
  
  it 'handles mappings' do
    mapping_type1 = Type.create(:mapping, key_type: :string, value_type: :bool)
    mapping_type2 = Type.create(:mapping, key_type: :uint256, value_type: mapping_type1)
    mapping = TypedVariable.create_or_validate(mapping_type2, {})
    
    expect(mapping[1]['hi']).to eq(false)
    expect(mapping[1]['hi'] = true).to eq(true)
    expect(mapping[1]['hi']).to eq(true)
    expect(mapping[1]['bye']).to eq(false)
    expect(mapping[1]['bye'] = true).to eq(true)
    expect(mapping[1]['bye']).to eq(true)
    expect(mapping[1]['hi']).to eq(true)
    expect(mapping[1]['a']).to eq(false)
    
    m_ary_type = ContractImplementation.mapping ({ uint256: ContractImplementation.array(:string, initial_length: 10) })
    map_array = TypedVariable.create_or_validate(Type.create(:mapping, key_type: :uint256, value_type: m_ary_type))
    
    expect(map_array[1][1][1]).to eq('')
  end
end
