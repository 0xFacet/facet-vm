require 'rails_helper'

RSpec.describe ForLoop do
  before(:all) do
    update_supported_contracts("ForLoopTest")
  end

  let(:bob) { "0x000000000000000000000000000000000000000b" }
  
  let(:test_contract_address) do
    address = trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: nil,
        data: {
          type: "ForLoopTest"
        }
      }
    ).address
  end
  
  describe '#forLoop' do
    it 'skips even numbers' do
      ret = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "skipEvenNumbers",
            args: [(1..10).to_a]
          }
        }
      ).return_value

      expect(ret).to eq([1, 3, 5, 7, 9])
    end

    it 'stops the loop when i is greater than 5' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "stopAtFive",
            args: [(1..10).to_a]
          }
        }
      ).return_value

      expect(result).to eq([0, 1, 2, 3, 4, 5])
    end

    it 'raises an error when max iterations are exceeded' do
      ary = (1..10).to_a
      
      result = trigger_contract_interaction_and_expect_error(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "testMaxIterations",
            args: [(1..10).to_a]
          }
        }
      )
    end
    
    it 'runs with default arguments' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "testDefaultArgs",
            args: [(1..10).to_a]
          }
        }
      ).return_value
      
      expect(result).to eq([0, 1, 2, 3, 4])
    end
    
    it 'decrements with a negative step' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "negativeStep",
            args: [(1..10).to_a]
          }
        }
      ).return_value
      expect(result).to eq([5, 4, 3, 2, 1, 0])
    end
    
    it 'never runs if condition is immediately false' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "conditionImmediatelyFalse",
            args: [(1..10).to_a]
          }
        }
      ).return_value
      expect(result).to be_empty
    end
    
    it 'increments by custom step value' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "customStepValue",
            args: [(1..10).to_a]
          }
        }
      ).return_value
      expect(result).to eq([0, 2, 4, 6, 8])
    end
    
    it 'handles nested forLoops correctly' do
      result = trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: "call",
          data: {
            to: test_contract_address,
            function: "nestedForLoops",
            args: [(1..10).to_a]
          }
        }
      ).return_value.with_indifferent_access
      
      expect(result[:outer]).to eq([0, 1, 2])
      expect(result[:inner]).to eq([10, 11, 12, 10, 11, 12, 10, 11, 12])
    end    
  end
end
