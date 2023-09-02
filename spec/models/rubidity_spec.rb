require 'rails_helper'

RSpec.describe AbiProxy::FunctionProxy, type: :model do
  describe '#convert_args_to_typed_variables_struct' do
    let(:function_proxy) do
      described_class.new(
        args: { arg1: :string, arg2: :uint256 },
        state_mutability: :non_payable,
        visibility: :internal,
        type: :function
      )
    end

    context 'when named parameters are passed' do
      let(:args) { { arg1: 'test', arg2: 123 } }

      it 'converts named parameters to typed variables struct' do
        result = function_proxy.convert_args_to_typed_variables_struct([], args)
        expect(result.arg1).to be_a(TypedVariable)
        expect(result.arg2).to be_a(TypedVariable)
      end
    end

    context 'when non-named parameters are passed' do
      let(:args) { ['test', 123] }

      it 'converts non-named parameters to typed variables struct' do
        result = function_proxy.convert_args_to_typed_variables_struct(args, {})
        expect(result.arg1).to be_a(TypedVariable)
        expect(result.arg2).to be_a(TypedVariable)
      end
    end
  end
  
  describe '#validate_arg_names' do
    let(:function_proxy) do
      described_class.new(
        args: { arg1: :string, arg2: :uint256 },
        state_mutability: :non_payable,
        visibility: :internal,
        type: :function
      )
    end

    context 'when all required arguments are passed' do
      let(:args) { { arg1: 'test', arg2: 123 } }

      it 'does not raise an error' do
        expect { function_proxy.validate_arg_names(args) }.not_to raise_error
      end
    end

    context 'when a required argument is missing' do
      let(:args) { { arg1: 'test' } }

      it 'raises a ContractArgumentError' do
        expect { function_proxy.validate_arg_names(args) }.to raise_error(ContractErrors::ContractArgumentError, /Missing arguments for: arg2/)
      end
    end

    context 'when an unexpected argument is passed' do
      let(:args) { { arg1: 'test', arg2: 123, arg3: 'unexpected' } }

      it 'raises a ContractArgumentError' do
        expect { function_proxy.validate_arg_names(args) }.to raise_error(ContractErrors::ContractArgumentError, /Unexpected arguments provided for: arg3/)
      end
    end
    
    context 'when all required arguments are passed as an array' do
      let(:args) { ['test', 123] }

      it 'does not raise an error' do
        expect { function_proxy.validate_arg_names(args) }.not_to raise_error
      end
    end

    context 'when a required argument is missing in the array' do
      let(:args) { ['test'] }

      it 'raises a ContractArgumentError' do
        expect { function_proxy.validate_arg_names(args) }.to raise_error(ContractErrors::ContractArgumentError, /Missing arguments for: arg2/)
      end
    end

    context 'when an extra argument is passed in the array' do
      let(:args) { ['test', 123, 'unexpected'] }

      it 'raises a ContractArgumentError' do
        expect { function_proxy.validate_arg_names(args) }.to raise_error(ContractErrors::ContractArgumentError, /Unexpected arguments provided for: unexpected/)
      end
    end
  end
  describe '#convert_args_to_typed_variables_struct' do
    let(:function_proxy) do
      described_class.new(
        args: { arg1: :string, arg2: :uint256 },
        state_mutability: :non_payable,
        visibility: :internal,
        type: :function
      )
    end

    context 'when named parameters are passed' do
      let(:args) { { arg1: 'test', arg2: 123 } }

      it 'converts named parameters to typed variables struct' do
        result = function_proxy.convert_args_to_typed_variables_struct(args, {})
        expect(result.arg1).to be_a(TypedVariable)
        expect(result.arg2).to be_a(TypedVariable)
      end
    end

    context 'when non-named parameters are passed' do
      let(:args) { ['test', 123] }

      it 'converts non-named parameters to typed variables struct' do
        result = function_proxy.convert_args_to_typed_variables_struct(args, {})
        expect(result.arg1).to be_a(TypedVariable)
        expect(result.arg2).to be_a(TypedVariable)
      end
    end

    context 'when a single string argument is passed' do
      let(:args) { 'test' }

      it 'converts the string argument to a typed variables struct' do
        result = function_proxy.convert_args_to_typed_variables_struct([args, nil], {})
        expect(result.arg1).to be_a(TypedVariable)
      end
    end
  end
end
