require 'rails_helper'

describe 'NameRegistry contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }
  
  before(:all) do
    RubidityFile.add_to_registry('spec/fixtures/StubERC20.rubidity')
  end
  
  it 'registers names' do
    weth_deploy = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20",
          args: { name: "WETH" }
        }
      }
    )
    
    weth_address = weth_deploy.address
    
    char_count_to_usd_cents_price_per_year = [
      1000_00, # 1 character
      500_00,  # 2 characters
      250_00,  # 3 characters, and so on...
      100_00   # 4 characters
    ]
    
    char_count_to_wei_usd_per_sec = char_count_to_usd_cents_price_per_year.map do |price_cents|
      (price_cents * 1.ether).div(365.days)
    end
    
    usd_wei_cents_in_one_eth = 1800_00 * 1.ether # 1800 USD in cents
    
    template = IO.read('/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/views/layouts/name_registry.html')
    
    registry_deploy = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "NameRegistry",
          args: {
            name: "Registry",
            symbol: "REG",
            trustedSmartContract: daryl,
            admin: user_address,
            usdWeiCentsInOneEth: usd_wei_cents_in_one_eth,
            charCountToUsdWeiCentsPrice: char_count_to_wei_usd_per_sec,
            cardTemplate: template,
            _WETH: weth_address
          }
        }
      }
    )
    
    registry_address = registry_deploy.address
    
    [user_address, alice, bob, charlie].each do |address|
      trigger_contract_interaction_and_expect_success(
        from: address,
        payload: {
          to: weth_address,
          data: {
            function: "mint",
            args: {
              amount: 1000.ether
            }
          }
        }
      )

      trigger_contract_interaction_and_expect_success(
        from: address,
        payload: {
          to: weth_address,
          data: {
            function: "approve",
            args: {
              spender: registry_address,
              amount: (2 ** 256 - 1)
            }
          }
        }
      )
    end
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "updateRegistrationPaused",
          args: false
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Only the admin can pause registration',
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "updateRegistrationPaused",
          args: true
        }
      }
    )
    
    reg_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "registerNameWithPayment",
          args: {
            to: user_address,
            name: "eve",
            durationInSeconds: 365.days
          }
        }
      }
    )
    
    max_len = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "maxNameLength"
    )
    
    ["Alice", "a_lice", "a" * (max_len + 1), ""].each do |invalid_name|
      trigger_contract_interaction_and_expect_error(
        error_msg_includes: 'Invalid name',
        from: alice,
        payload: {
          to: registry_address,
          data: {
            function: "registerNameWithPayment",
            args: {
              to: alice,
              name: invalid_name,
              durationInSeconds: 365.days
            }
          }
        }
      )
    end
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Name not available',
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "registerNameWithPayment",
          args: {
            to: alice,
            name: "eve",
            durationInSeconds: 365.days
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "registerNameWithPayment",
          args: {
            to: alice,
            name: "alice",
            durationInSeconds: 365.days
          }
        }
      }
    )
    
    initial_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    duration_in_seconds = 28.days
    name = "ali"
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "registerNameWithPayment",
          args: {
            to: alice,
            name: name,
            durationInSeconds: duration_in_seconds
          }
        }
      }
    )
    
    final_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    name_length = name.length

    # This is the rate in wei dollars per second for the given name length
    rate_wei_usd_per_sec = char_count_to_wei_usd_per_sec[name_length - 1]
    
    # Calculate the total price in wei dollars for the given duration
    total_price_wei_dollars = rate_wei_usd_per_sec * duration_in_seconds
    
    # Convert the total price from wei dollars to wei, now using the rate in wei cents
    price_in_wei = (total_price_wei_dollars * 1.ether).div(usd_wei_cents_in_one_eth)
    
    # Now calculate the expected final balance
    expected_final_balance = initial_balance - price_in_wei
    
    expect(final_balance).to eq(expected_final_balance)
    
    rewew_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "renewNameWithPayment",
          args: {
            name: "eve",
            durationInSeconds: 10.days
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "setUserDetails",
          args: {
            realName: "Alice",
            bio: "Alice's bio",
            imageURI: "http://example.com/alice.jpg",
            links: ["http://alice.com"]
          }
        }
      }
    )
  
    user_details = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "getUserDetails",
      function_args: { user: alice }
    )
  
    expect(user_details).to eq({
      realName: "Alice",
      bio: "Alice's bio",
      imageURI: "http://example.com/alice.jpg",
      links: ["http://alice.com"]
    }.stringify_keys)
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "transferFrom",
          args: {
            from: user_address,
            to: bob,
            id: 1
          }
        }
      }
    )
  
    new_owner = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "ownerOf",
      function_args: { id: 1 }
    )
  
    expect(new_owner).to eq(bob)
    
    token_uri = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "tokenURI",
      function_args: 1
    )
    
    resolved_address = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "resolveName",
      function_args: { name: "alice" }
    )
    
    expect(resolved_address).to eq(alice)
    
    is_available = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "nameAvailable",
      function_args: { name: "john" }
    )
    
    expect(is_available).to be true
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: registry_address,
        data: {
          function: "registerNameWithPayment",
          args: {
            to: bob,
            name: "shortdurationname",
            durationInSeconds: 28.days
          }
        }
      }
    )
    
    id = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "nameToTokenId",
      function_args: "shortdurationname"
    )
    
    expect {
      ContractTransaction.make_static_call(
        block_timestamp: 30.days.from_now,
        contract: registry_address,
        function_name: "resolveName",
        function_args: "shortdurationname"
      )
    }.to raise_error(Contract::StaticCallError, /Name expired/)
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Name expired',
      block_timestamp: 30.days.from_now,
      from: bob,
      payload: {
        to: registry_address,
        data: {
          function: "transferFrom",
          args: {
            from: bob,
            to: alice,
            id: id
          }
        }
      }
    )
  end
end
