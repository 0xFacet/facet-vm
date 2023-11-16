require 'rails_helper'

RSpec.describe "UniswapV2Pair", type: :model do
  before(:all) do
    update_supported_contracts("UniswapV2CalleeTester")
  end
  
  it 'executes the Uniswap V2 process' do
    # Deploy the ERC20 tokens
    tokenA_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: nil,
        data: {
          type: "PublicMintERC20",
          args: {
            name: "Token0",
            symbol: "TK0",
            maxSupply: 21e24.to_i,
            perMintLimit: 21e24.to_i,
            decimals: 18
          }
        }
      }
    )

    tokenB_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: nil,
        data: {
          type: "PublicMintERC20",
          args: {
            name: "Token1",
            symbol: "TK1",
            maxSupply: 21e24.to_i,
            perMintLimit: 21e24.to_i,
            decimals: 18
          }
        }
      }
    )

    # Deploy the UniswapV2Factory contract 
    factory_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: nil,
        data: {
          type: "UniswapV2Factory",
          args: { _feeToSetter: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97" }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "setFeeTo",
          args: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
        }
      }
    )

    # Create a pair using the UniswapV2Factory contract
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "createPair",
          args: {
            tokenA: tokenA_deploy_receipt.address, 
            tokenB: tokenB_deploy_receipt.address
          }
        }
      }
    )
# binding.pry
    pair_address = create_pair_receipt.logs.find { |log| log['event'] == 'PairCreated' }['data']['pair']

    # The user decides how much liquidity they would provide
    
    deploy_receipts = {
      "tokenA": tokenA_deploy_receipt,
      "tokenB": tokenB_deploy_receipt,
    }.with_indifferent_access
  # binding.pry
    # Approve the Pair contract to spend the user's tokens
    [:tokenA, :tokenB].each do |token|
      trigger_contract_interaction_and_expect_success(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        payload: {
          to: deploy_receipts[token].address,
          data: {
            function: "mint",
            args: {
              amount: 1000e18.to_i
            }
          }
        }
      )
      
      approval_receipt = trigger_contract_interaction_and_expect_success(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        payload: {
          to: deploy_receipts[token].address,
          data: {
            function: "approve",
            args: {
              spender: pair_address,
              amount: 1000e18.to_i
            }
          }
        }
      )
    end
  
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: deploy_receipts["tokenA"].address,
        data: {
          function: "transfer",
          args: {
            to: pair_address,
            amount: 300e18.to_i
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: deploy_receipts["tokenB"].address,
        data: {
          function: "transfer",
          args: {
            to: pair_address,
            amount: 600e18.to_i
          }
        }
      }
    )
    
    # Add liquidity to the pair
    add_liquidity_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "mint",
          args: {
            to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
          }
        }
      }
    )
    
    expect(add_liquidity_receipt.logs).to include(hash_including('event' => 'Mint'))
    
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "transfer",
          args: {
            to: pair_address,
            amount: 100e18.to_i
          }
        }
      }
    )
    
    burn_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",    # same address that minted the liquidity
      payload: {
        to: pair_address,
        data: {
          function: "burn",
          args: { to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97" }  # withdrawn assets are sent to this address 
        }
      }
    )
    
    expect(burn_receipt.logs).to include(hash_including('event' => 'Burn'))
    
    r = trigger_contract_interaction_and_expect_error(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "burn",
          args: { to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97" }
        }
      }
    )
    
    approve_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: tokenA_deploy_receipt.address,
        data: {
          function: "approve",
          args: {
            spender: pair_address,
            amount: 500e18.to_i
          }
        }
      }
    )
    
    inputAmount = 200e18.to_i
    
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: deploy_receipts["tokenB"].address,
        data: {
          function: "transfer",
          args: {
            to: pair_address,
            amount: inputAmount
          }
        }
      }
    )
    
    extraAmount = 10
    
    UniswapV2CalleeTester = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: nil,
        data: {
          type: "UniswapV2CalleeTester",
          args: [pair_address, extraAmount]
        }
      }
    ).address
    
    reserves = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "getReserves"
    )
    
    reserveA, reserveB = reserves.values_at("_reserve0", "_reserve1")
    
    numerator = inputAmount * 997 * reserveA;
    denominator = (reserveB * 1000) + (inputAmount * 997);
    expectedOut = numerator.div(denominator)
    
    expectedOut += extraAmount
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "swap",
          args: {
            amount0Out: expectedOut,
            amount1Out: 0,
            to: UniswapV2CalleeTester,
            data: "0x01"
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: deploy_receipts["tokenA"].address,
        data: {
          function: "transfer",
          args: {
            to: pair_address,
            amount: 50e18.to_i
          }
        }
      }
    )

    # Execute skim
    skim_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "skim",
          args: { to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97" } # Address where extra tokens should go
        }
      }
    )

    expect(skim_receipt.logs).to include(hash_including('event' => 'Transfer'))
    
    sync_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: pair_address,
        data: {
          function: "sync",
          args: {}
        }
      }
    )
  end
end
