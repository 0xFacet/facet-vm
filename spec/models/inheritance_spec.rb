require 'rails_helper'

RSpec.describe AbiProxy, type: :model do
  before do
    unless defined?(Contracts::TestContract)
      class Contracts::TestContract < ContractImplementation
        is :ERC20
        
        string :public, :definedInTest

        constructor(
          name: :string,
          symbol: :string,
          decimals: :uint8
        ) {
          ERC20.constructor(name: name, symbol: symbol, decimals: decimals)
        }
        
        function :_mint, { to: :address, amount: :uint256 }, :public, :virtual, :override do
          ERC20._mint(to: to, amount: amount)
          s.definedInTest = "definedInTest"
        end
        
        function :nonVirtual, {}, :public do
        end
      end
    end

    unless defined?(Contracts::TestContractNoOverride)
      class Contracts::TestContractNoOverride < ContractImplementation
        is :ERC20
        
        constructor(
          name: :string,
          symbol: :string,
          decimals: :uint8
        ) {
          ERC20.constructor(name: name, symbol: symbol, decimals: decimals)
        }
      end
    end
    
    unless defined?(Contracts::TestContractMultipleInheritance)
      class Contracts::NonToken < ContractImplementation
        string :public, :definedInNonToken
        
        constructor() {}
        
        event :Greet, { greeting: :string }
        
        function :_mint, { to: :address, amount: :uint256 }, :public, :virtual do
          emit :Greet, greeting: "Hello"
          s.definedInNonToken = "definedInNonToken"
        end
      end
    end
    
    unless defined?(Contracts::TestContractMultipleInheritance)
      class Contracts::TestContractMultipleInheritance < ContractImplementation
        is :TestContract, :NonToken
        
        string :public, :definedHere
  
        constructor(
          name: :string,
          symbol: :string,
          decimals: :uint8
        ) {
          TestContract.constructor(name: name, symbol: symbol, decimals: decimals)
          NonToken.constructor()
          
          s.definedHere = "definedHere"
        }
  
        function :_mint, { to: :address, amount: :uint256 }, :public, :override do
          TestContract._mint(to: to, amount: amount)
          NonToken._mint(to: to, amount: amount)
          ERC20._mint(to: to, amount: amount)
        end
      end
    end
  end
  
  it "won't deploy abstract contract" do
    deploy_receipt = trigger_contract_interaction_and_expect_deploy_error(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "ERC20",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )
  end
  
  it "allows a child contract to override a parent contract's function" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContract",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )

    call_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
  end

  it "does not allow a child contract to call a parent contract's function without overriding it" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContractNoOverride",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )

    trigger_contract_interaction_and_expect_call_error(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
  end
  
  it "allows a child contract to override a parent contract's function and call the parent contract's function using the _PARENT prefix" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContractMultipleInheritance",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )
  
    call_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
    
    expect(call_receipt.logs.map{|i| i['event']}.sort)
    .to eq(['Greet', 'Transfer', 'Transfer'].sort)
    
    expect(call_receipt.contract.current_state.state['totalSupply']).to eq(10)
    
    expect(call_receipt.contract.current_state.state.
      slice('definedHere', 'definedInTest', 'definedInNonToken').values.sort).to eq(
        ['definedHere', 'definedInTest', 'definedInNonToken'].sort
      )
  end
  
  it "raises an error when declaring override without overriding anything" do
    expect {
      class Contracts::TestContractOverrideNonVirtual < ContractImplementation
        function :_mint, {}, :public, :override do
        end
      end
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when trying to override a non-virtual function" do
    expect {
      class Contracts::TestContractOverrideNonVirtual < ContractImplementation
        is :TestContract
  
        function :nonVirtual, {}, :public, :override do
          ERC20._mint(to: to, amount: amount)
        end
      end
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when trying to override a virtual function without the override modifier" do
    expect {
      class Contracts::TestContractOverrideWithoutModifier < ContractImplementation
        is :TestContract
  
        function :_mint, { to: :address, amount: :uint256 }, :public do
          _TestContract._mint(to: to, amount: amount)
        end
      end
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when defining the same function twice in a contract" do
    expect {
      class Contracts::TestContractDuplicateFunction < ContractImplementation
        function(:_mint, { to: :address, amount: :uint256 }, :public) {}
        function(:_mint, { to: :address, amount: :uint256 }, :public) {}
      end
    }.to raise_error(ContractErrors::FunctionAlreadyDefinedError)
  end
end
