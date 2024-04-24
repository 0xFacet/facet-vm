require 'rails_helper'

describe 'NameRegistry contract' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }
  
  before(:all) do
    update_supported_contracts("StubERC20")
    update_supported_contracts("NameRegistry01")
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
      10_000_00, 1_000_00, 500_00, 100_00, 10_00,
    ]
    
    char_count_to_wei_usd_per_sec = char_count_to_usd_cents_price_per_year.map do |price_cents|
      (price_cents * 1.ether).div(365.days.to_i)
    end
    
    usd_wei_cents_in_one_eth = 1800_00 * 1.ether # 1800 USD in cents
    
    template = Rails.root.join("spec/fixtures/name_registry.html").read
    
    registry_deploy = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "NameRegistry01",
          args: {
            name: "Registry",
            symbol: "REG",
            owner: user_address,
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
          function: "unpause"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'NameRegistry01 error: msg.sender is not the owner',
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "unpause"
        }
      }
    )
    
    mark = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "markPreregistrationComplete"
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
          function: "setCardDetails",
          args: {
            tokenId: 3,
            displayName: "Alice",
            bio: "Alice's bio",
            imageURI: "http://example.com/alice.jpg",
            links: ["http://alice.com"]
          }
        }
      }
    )
    
    user_details = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "getCardDetails",
      function_args: { tokenId: 3 }
    )
  
    expect(user_details).to eq({
      displayName: "Alice",
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
    
    travel_to Time.now + 31.days
    
    expect {
      ContractTransaction.make_static_call(
        contract: registry_address,
        function_name: "resolveName",
        function_args: "shortdurationname"
      )
    }.to raise_error(Contract::StaticCallError, /Name expired/)
    
    travel_to Time.now - 31.days
    
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
    
    key = Eth::Key.new(priv: "38bf75dd68c41bd5f586218f130ebecc4fe5f1adfdfb3f9a8dabcb84e557dad8")
    signer = key.address.address
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: registry_address,
        data: {
          function: "createSticker",
          args: {
            name: "First Sticker",
            description: "A test sticker",
            imageURI: "data:image/png;base64,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",
            stickerExpiry: 100.years.from_now.to_i,
            grantingAddress: signer
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: registry_address,
        data: {
          function: "createSticker",
          args: {
            name: "Second Sticker",
            description: "Another test sticker",
            imageURI: "",
            stickerExpiry: 100.years.from_now.to_i,
            grantingAddress: signer
          }
        }
      }
    )
    
    types = {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" }
      ],
      StickerClaim: [
        { name: "stickerId", type: "uint256" },
        { name: "claimer", type: "address" },
        { name: "deadline", type: "uint256" }
      ]
    }
    
    deadline = Time.current.to_i + 1000
    
    data = {
      types: types,
      domain: {
        name: "Registry",
        version: "1",
        chainId: chainid,
        verifyingContract: registry_address
      },
      primaryType: "StickerClaim",
      message: {
        stickerId: 1,
        claimer: user_address,
        deadline: deadline
      }
    }
    
    hashed_data = Eth::Eip712.hash(data)

    signature = key.sign(hashed_data)
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "claimSticker",
          args: {
            stickerId: 1,
            deadline: deadline,
            signature: "0x" + signature,
            tokenId: 0,
            position: [0, 0]
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Invalid signature',
      from: alice,
      payload: {
        to: registry_address,
        data: {
          function: "claimSticker",
          args: {
            stickerId: 2,
            deadline: deadline,
            signature: "0x" + signature,
            tokenId: 0,
            position: [0, 0]
          }
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
            name: "stickerfan",
            durationInSeconds: 365.days
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "placeSticker",
          args: {
            stickerId: 1,
            tokenId: 5,
            position: [20, 20]
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "setCardDetails",
          args: {
            tokenId: 5,
            displayName: "Joey Joe Joe",
            bio: "JJ bio",
            imageURI: "http://example.com",
            links: ["http://twitter.com/JJ", "http://instagram.com/realJJ"]
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "updateCardTemplate",
          args: ''
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "updateCardTemplate",
          args: template
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "setDefaultRoyalty",
          args: [user_address, 500]
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "deleteDefaultRoyalty"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "setTokenRoyalty",
          args: [0, user_address, 500]
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: registry_address,
        data: {
          function: "deleteTokenRoyalty",
          args: 0
        }
      }
    )
    
    token_uri = ContractTransaction.make_static_call(
      contract: registry_address,
      function_name: "tokenURI",
      function_args: 5
    )
    
    # Clipboard.copy(JSON.parse(token_uri[/.*?,(.*)/, 1])['animation_url'])
    # puts JSON.parse(token_uri[/.*?,(.*)/, 1])['animation_url']
  end
end
