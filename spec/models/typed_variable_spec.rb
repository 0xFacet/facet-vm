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
      expect(TypedVariable.create_or_validate(:uint256, typed_variable)).to be_a(TypedVariable)
    end

    it 'creates a new TypedVariable if the value is not a TypedVariable' do
      expect(TypedVariable.create_or_validate(:uint256, 1)).to be_a TypedVariable
    end
    
    it 'raises a VariableTypeError if the value is a TypedVariable and its type cannot be assigned from the specified type' do
      typed_variable = TypedVariable.create(:uint256, 2**128) # This value is too large for uint128
      expect { TypedVariable.create_or_validate(:uint128, typed_variable) }.to raise_error(ContractErrors::VariableTypeError)
    end
  end
end
