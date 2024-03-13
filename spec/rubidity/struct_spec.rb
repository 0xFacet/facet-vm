require 'rails_helper'

RSpec.describe StructDefinition, type: :model do
  let(:alice) { "0x000000000000000000000000000000000000000a" }

  before(:all) do
    update_supported_contracts("TestStruct")
  end
  
  describe 'Basic Functionality' do
    it 'verifies contract interactions and state changes' do
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
            args: { _age: 20 }
          }
        }
      )
      
      updated_age = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getAge",
        function_args: {}
      )
      expect(updated_age).to eq(20)
      
      person_before_update = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      ).with_indifferent_access
      expect(person_before_update[:name]).to eq("Bob")
      expect(person_before_update[:age]).to eq(20) # Reflects the updated age
      
      name_from_person = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getName",
        function_args: {
          _person: {
            name: "Charlie",
            age: 21
          }
        }
      )
      expect(name_from_person).to eq("Charlie")
      
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
      
      person_after_first_update = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      ).with_indifferent_access
      expect(person_after_first_update[:name]).to eq("Daryl")
      expect(person_after_first_update[:age]).to eq(111)
      
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
      
      person_after_second_update = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPerson",
        function_args: {}
      ).with_indifferent_access
      expect(person_after_second_update[:name]).to eq("Ethan")
      expect(person_after_second_update[:age]).to eq(333)
      
      person_from_address = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPersonFromAddress",
        function_args: { address: "1600 Penn" }
      ).with_indifferent_access
      # Assuming the address mapping was not updated, it should still return the initial person's state
      expect(person_from_address[:name]).to eq("Bob")
      expect(person_from_address[:age]).to eq(42)
      
      movie_fans = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getAllMovieFans",
        function_args: {}
      ).map(&:with_indifferent_access)
      # binding.pry
      expect(movie_fans.size).to eq(2)
      
      expect(movie_fans[0][:name]).to eq("Robert")
      expect(movie_fans[0][:age]).to eq(20)
      
      expect(movie_fans[1][:name]).to eq("Roberta")
      expect(movie_fans[1][:age]).to eq(30)
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "addMovieFan",
            args: {
              _fan: {
                name: "Z",
                age: 1
              }
            }
          }
        }
      )
      
      movie_fans = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getAllMovieFans",
        function_args: {}
      ).map(&:with_indifferent_access)
      
      expect(movie_fans.size).to eq(3)
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setPersonFromAddress",
            args: {
              address: "1600 Penn",
              _person: {}
            }
          }
        }
      )
      
      person_from_address = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPersonFromAddress",
        function_args: { address: "1600 Penn" }
      ).with_indifferent_access
      # Assuming the address mapping was not updated, it should still return the initial person's state
      expect(person_from_address[:name]).to eq("")
      expect(person_from_address[:age]).to eq(0)
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setPersonAgeFromAddress",
            args: {
              address: "1600 Penn",
              _age: 1
            }
          }
        }
      )
      
      person_from_address = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "getPersonFromAddress",
        function_args: { address: "1600 Penn" }
      ).with_indifferent_access
      # Assuming the address mapping was not updated, it should still return the initial person's state
      expect(person_from_address[:name]).to eq("")
      expect(person_from_address[:age]).to eq(1)
      
      person = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "movieFans",
        function_args: 0
      ).with_indifferent_access
      
      expect(person[:name]).to eq("Robert")
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setFan",
            args: {
              _index: 0,
              _fan: {}
            }
          }
        }
      )
      
      person = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "movieFans",
        function_args: 0
      ).with_indifferent_access
      
      expect(person[:name]).to eq("")
      
      person = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "movieFans",
        function_args: 1
      ).with_indifferent_access
      
      expect(person[:name]).to eq("Roberta")
      
      trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: "call",
          data: {
            to: c.address,
            function: "setFanName",
            args: {
              _index: 1,
              _name: "Alice"
            }
          }
        }
      )
      
      person = ContractTransaction.make_static_call(
        contract: c.address,
        function_name: "movieFans",
        function_args: 1
      ).with_indifferent_access
      
      expect(person[:name]).to eq("Alice")
    end

  end
end