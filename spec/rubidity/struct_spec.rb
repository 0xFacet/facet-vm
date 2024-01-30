require 'rails_helper'

RSpec.describe StructDefinition, type: :model do
  let(:alice) { "0x000000000000000000000000000000000000000a" }

  before(:all) do
    update_supported_contracts("TestStruct")
  end
  
  describe '#can_be_assigned_from?' do
    it 'returns true if types are the same' do
      c = trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: :create,
          data: {
            type: "TestStruct",
            args: {}
          }
        }
      )
      
      initial_age = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getAge",
        function_args: {}
      )
      expect(initial_age).to eq(42)
          
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setAge",
            args: 20
          }
        }
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getAge",
        function_args: {}
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getName",
        function_args: {
          _person: {
            name: "Charlie",
            age: 21
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setPerson",
            args: {
              _person: {
                name: "Daryl",
                age: 111
              }
            }
          }
        }
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      )
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setPersonVerbose",
            args: {
              name: "Ethan",
              age: 333
            }
          }
        }
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      )
      
      ap ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPersonFromAddress",
        function_args: "1600 Penn"
      )
    end
  end
end
