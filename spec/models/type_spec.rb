# spec/models/type_spec.rb
require 'rails_helper'

RSpec.describe Type, type: :model do
  describe '#can_be_assigned_from?' do
    it 'returns true if types are the same' do
      type = Type.create(:uint256)
      expect(type.can_be_assigned_from?(Type.create(:uint256))).to be true
    end

    it 'returns true if both types are integer types and the number of bits of the first type is greater than or equal to the number of bits of the second type' do
      type = Type.create(:uint256)
      expect(type.can_be_assigned_from?(Type.create(:uint128))).to be true
    end

    it 'returns false otherwise' do
      type = Type.create(:uint128)
      expect(type.can_be_assigned_from?(Type.create(:uint256))).to be false
    end
    
    it 'returns true if a literal can be assigned to the type' do
      type = Type.create(:uint256)
      literal = 123
      typed_variable = TypedVariable.create_or_validate(type, literal)
      expect(type.can_be_assigned_from?(typed_variable.type)).to be true
    end
  
    it 'raises a VariableTypeError if a literal cannot be assigned to the type' do
      type = Type.create(:uint256)
      literal = "abcd" # This is a string, not an integer
      expect { TypedVariable.create_or_validate(type, literal) }.to raise_error(
        ContractErrors::VariableTypeError
      )
    end
  end
  
  describe '#values_can_be_compared?' do
    it 'returns true if types are compatible' do
      type = Type.create(:uint256)
      expect(type.values_can_be_compared?(Type.create(:uint256))).to be true
    end
  
    it 'returns true if both types are integer types' do
      type = Type.create(:uint256)
      expect(type.values_can_be_compared?(Type.create(:uint128))).to be true
    end
  
    it 'returns false otherwise' do
      type = Type.create(:uint128)
      expect(type.values_can_be_compared?(Type.create(:address))).to be false
    end
    
    it 'returns true if a literal can be compared with the type' do
      type = Type.create(:uint256)
      literal = 123
      typed_variable = TypedVariable.create_or_validate(type, literal)
      expect(type.values_can_be_compared?(typed_variable.type)).to be true
    end
  
    it 'returns false if a literal cannot be compared with the type' do
      type = Type.create(:uint256)
      literal = "abcd" # This is a string, not an integer
      expect { TypedVariable.create_or_validate(type, literal) }.to raise_error(
        ContractErrors::VariableTypeError
      )
    end
  end
end
