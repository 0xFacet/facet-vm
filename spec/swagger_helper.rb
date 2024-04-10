# frozen_string_literal: true

require 'rails_helper'
require './spec/support/api_common_parameters'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Facet API V2',
        version: 'v2',
        description: <<~DESC
        ## Overview

        Welcome to the Facet API Docs!
        
        The Facet API enables you to query a [Facet Virtual Machine](https://github.com/0xFacet/facet-vm) for the state of the Facet protocol. This API is available on any instance of the Facet VM, but you can use it for free at the official endpoint [https://api.facet.org/v2](https://api.facet.org/v2).
        
        The Facet VM's state is determined by special Ethereum transactions sent to `0x00000000000000000000000000000000000face7`. These transactions have payloads like:
        
        ```json
        data:application/vnd.facet.tx+json;rule=esip6, {
            "op": "call",
            "data": {
                "to": "0xa848fe8a6658b45a63855868cb2fab62a03a6f49",
                "function": "mint",
                "args": {
                    "amount": "1000000000000000000000"
                }
            }
        }
        ```
        
        When interpreted according to the Facet protocol they represent user intents to, for example, mint a token. Using protocol rules the Facet VM determines whether an intent should be satisfied and if so updates its internal state.
        
        In addition to querying the state of the Facet VM, you can also simulate transactions to forecast outcomes, catch errors early, and ensure your interactions proceed as expected.
        
        ## Core Concepts
        
        - **Transactions:** Every Facet transaction is an Ethereum transaction, so you can look up Facet transactions on Etherscan as well as using the Facet API. However the Facet API provides the Facet interpretation of the transaction, including the "Dumb Contract" that was called, the arguments to the call, and the result.
        
        - **Contracts:** The term "contracts" in Facet refers to "Dumb Contracts." These contracts perform all the same contracts as Smart Contracts but their logic is executed off-chain. In these endpoints you can query contract ABIs, states, and other familiar fields.
        
        - **Simulated Transactions:** Submit your Facet transaction to the API before executing it on chain to make sure it will succeed. The API will return the result of the transaction as if it were executed on chain.
        
        ## Community and Support
        
        Join our community on [GitHub](https://github.com/0xFacet/facet-vm) and [Discord](https://discord.gg/facet) to contribute, get support, and share your experiences with the Facet VM.
        DESC
      },
      tags: [
        {
          name: 'Transactions',
          description: 'Endpoints for querying Facet transactions.'
        },
        {
          name: 'Contracts',
          description: 'Endpoints for querying contracts and simulating transactions.'
        },
        {
          name: 'Contract Calls',
          description: 'Endpoints for querying internal and external contract calls. A Transaction consists of multiple Contract Calls.'
        },
        {
          name: 'Blocks',
          description: 'Operations related to blockchain blocks.'
        },
        {
          name: 'Status',
          description: 'Endpoints for querying the status of the VM.'
        },
        # {
        #   name: 'Tokens',
        #   description: 'Endpoints for querying token balances, token transfers, and token metadata. Useful for understanding the token-related activities of a user.'
        # },
        # {
        #   name: 'Wallets',
        #   description: 'Endpoints for managing and querying wallet information. Includes functionalities like retrieving a user’s wallet balance across different tokens.'
        # },
        # {
        #   name: 'Name Registries',
        #   description: 'Endpoints for interacting with name registry services, such as Facet Cards. Allows for querying and registering human-readable names linked to blockchain addresses.'
        # },
      ],
      # "x-tagGroups": [
      #   {
      #     name: "Core API",
      #     tags: [
      #       "Contracts",
      #       "Transactions",
      #       "Contract Calls",
      #       "Blocks",
      #       "Status"
      #     ]
      #   },
      #   {
      #     name: "Extensions",
      #     tags: [
      #       "Tokens",
      #       "Wallets",
      #       "Name Registries"
      #     ]
      #   }
      # ],
      paths: {},
      components: {
        schemas: {
          BlockObject: {
            type: :object,
            properties: {
              block_number: { type: :integer, example: 18680069, description: 'Unique number identifying the block.' },
              timestamp: { type: :integer, example: 1701294755, description: 'Timestamp for when the block was created.' },
              blockhash: { type: :string, example: '0x0d4f54a2eccaff738585457aa55e281a1732519d9c884f9ca1e606b64315048b', description: 'Hash of the block.' },
              parent_blockhash: { type: :string, example: '0x0c65bd77b118e87b42ab3472368a5bfb48a40167befc6c2e3c02925bfc161f26', description: 'Hash of the parent block.' },
              imported_at: { type: :string, format: 'date-time', example: '2024-02-12T22:04:00.404Z', description: 'The timestamp when the block was imported into the system.' },
              processing_state: { type: :string, example: 'complete', description: 'Current processing state of the block.' },
              transaction_count: { type: :integer, example: 1, description: 'Number of transactions in the block.' },
              runtime_ms: { type: :integer, example: 17, description: 'Time taken to process the block, in milliseconds.' }
            }
          },
          ContractCallObject: {
            type: :object,
            properties: {
              transaction_hash: { type: :string, example: '0x110f94fddfba0252a01ecd6a08ccc3cd764980980689477c94021c14ecbf9be2' },
              internal_transaction_index: { type: :integer, example: 13 },
              effective_contract_address: { type: :string, example: '0x55ab0390a89fed8992e3affbf61d102490735e24' },
              function: { type: :string, example: 'transfer' },
              args: {
                '$ref' => '#/components/schemas/ContractFunctionArgs'
              },
              call_type: { type: :string, example: 'call' },
              return_value: { '$ref' => '#/components/schemas/ContractFunctionReturnValue' },
              logs: {
                type: :array,
                items: { '$ref' => '#/components/schemas/LogEntryObject' }
              },
              error: { type: :string, nullable: true },
              status: { type: :string },
              block_number: { type: :integer },
              block_timestamp: { type: :integer },
              block_blockhash: { type: :string },
              transaction_index: { type: :integer },
              runtime_ms: { type: :integer },
              to: { type: :string },
              from: { type: :string },
              contract_address: { type: :string, nullable: true },
              to_or_contract_address: { type: :string }
            }
          },
          ContractObject: {
            type: :object,
            properties: {
              transaction_hash: {
                type: :string,
                example: '0x93ea51222f41418dad2159517b4f82dd02e52c766a3a528f587acf1035b8d94d',
                description: 'Hash of the transaction that deployed the contract.'
              },
              current_type: { type: :string, example: 'PublicMintERC20' },
              current_init_code_hash: { type: :string, example: '0xb1b0ed1e4a8c9c9b0210f267137e368f782453e41f622fa8cf68296d04c84c88' },
              address: { type: :string, example: '0xd5d49b065b6c187b799073ffbb52f93a6dfdc758' },
              abi: {
                type: :array,
                items: {
                  type: :object,
                  description: "An array of objects, each representing a contract's ABI element. The structure can vary significantly, including fields like 'inputs', 'name', 'type', 'outputs', and so on, reflecting the contract's functions and events.",
                  additionalProperties: true
                },
                description: "The contract's ABI, detailing its functions, events, and constructors. The exact structure of each element in the ABI array depends on the contract's design.",
                example: [
                  {
                    "inputs": [
                      {
                        "name": "_factory",
                        "type": "address"
                      },
                      {
                        "name": "_WETH",
                        "type": "address"
                      },
                      {
                        "name": "protocolFeeBPS",
                        "type": "uint256"
                      },
                      {
                        "name": "initialPauseState",
                        "type": "bool"
                      }
                    ],
                    "overrideModifiers": [],
                    "outputs": [],
                    "stateMutability": "non_payable",
                    "type": "constructor",
                    "visibility": nil,
                    "fromParent": false,
                    "name": "constructor"
                  }
                ]
              },
              source_code: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    language: { type: :string },
                    code: { type: :string }
                  }
                }
              },
              deployment_transaction: { '$ref' => '#/components/schemas/TransactionObject' },
            }
          },      
          TransactionObject: {
            type: :object,
            properties: {
              transaction_hash: { type: :string, example: '0x22c0b2b290cf90e95544be81ad93fe0a304af3d01652f45e3610f40ae2068185' },
              from: { type: :string, example: '0xe4fad47541c224bc9af3f06863d9fcc2ef47e65e' },
              to: {
                type: :string,
                example: '0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e',
                description: 'The contract the transaction was sent to. Blank if the transaction created a contract'
              },
              effective_contract_address: {
                type: :string,
                example: '0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e',
                description: 'Address of the contract that the transaction interacts with. Ether the contract the transaction was sent to or the contract the transaction created.'
              },
              created_contract_address: {
                type: :string,
                example: '0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e',
                description: 'Address of the contract created by the transaction. Present only if the transaction created a contract.'
              },
              function: { type: :string, example: 'swapExactTokensForTokens' },
              args: {
                '$ref' => '#/components/schemas/ContractFunctionArgs'
              },
              logs: {
                type: :array,
                items: { '$ref' => '#/components/schemas/LogEntryObject' },
              },
              status: { type: :string, example: 'success' },
              error: { type: :string, nullable: true, example: nil },
              return_value: { '$ref' => '#/components/schemas/ContractFunctionReturnValue' },
              call_type: { type: :string, example: 'call' },
              gas_price: { type: :integer, example: 34801480344 },
              gas_used: { type: :integer, example: 25896 },
              transaction_fee: { type: :integer, example: 901219134988224 },
              block_timestamp: { type: :integer, example: 1712329319 },
              block_number: { type: :integer, example: 19590300 },
              transaction_index: { type: :integer, example: 131 },
              block_blockhash: { type: :string, example: '0x13c0159d7e238f7f562dc11cbbff0d762c4d1d0feceabe70f29ff560eb78e465' },
              runtime_ms: { type: :integer, example: 292 },
            }
          },
          SimulateTransactionResponse: {
            type: :object,
            properties: {
              transaction_receipt: { '$ref' => '#/components/schemas/TransactionObject' },
              internal_transactions: { 
                type: :array,
                items: { '$ref' => '#/components/schemas/ContractCallObject' }
              },
              ethscription_status: { type: :string, example: 'success' },
              ethscription_error: { type: :string, nullable: true },
              ethscription_content_uri: { type: :string, example: 'data:application/vnd.facet.tx+json;rule=esip6,{}' }
            }
          },
          ContractFunctionArgs: {
            oneOf: [
              {
                type: :array,
                items: { type: :string },
                example: ["MyToken", "MTK", "18"],
                description: 'Arguments passed to the function in order.'
              },
              {
                type: :object,
                additionalProperties: {
                  type: :string,
                },
                example: { name: "MyToken", symbol: "MTK", decimals: "18" },
                description: 'Arguments passed to the function as key-value pairs.'
              }
            ]
          },
          ContractFunctionReturnValue: {
            oneOf: [
              {
                type: :string,
                description: 'Return value as a string.',
                example: "123"
              },
              {
                type: :object,
                additionalProperties: {
                  type: :string,
                },
                example: { name: "MyToken", symbol: "MTK", decimals: "18" },
                description: 'Named return values as an object.'
              }
            ] 
          },
          LogEntryObject: {
            type: :object,
            properties: {
              data: {
                type: :object,
                additionalProperties: {
                  type: :object
                },
                description: 'Data emitted by the event. Structure varies by event type.',
                example: {
                  owner: '0x1673540243e793b0e77c038d4a88448eff524dce',
                  amount: 100,
                  spender: '0x55ab0390a89fed8992e3affbf61d102490735e24'
                }
              },
              event: {
                type: :string,
                example: 'Transfer',
                description: 'Name of the emitted event.'
              },
              index: {
                type: :integer,
                example: 6,
                description: 'Index of the log entry.'
              },
              contractType: {
                type: :string,
                example: 'EtherBridge03',
                description: 'Type of the emitting contract.'
              },
              contractAddress: {
                type: :string,
                example: '0x1673540243e793b0e77c038d4a88448eff524dce',
                description: 'Address of the emitting contract.'
              }
            }
          },
          PaginationObject: {
            type: :object,
            properties: {
              page_key: { type: :string, example: '18680069-4-1', description: 'Key for the next page of results. Supply this in the page_key query parameter to retrieve the next set of items.' },
              has_more: { type: :boolean, example: true, description: 'Indicates if more items are available beyond the current page.' }
            },
            description: 'Contains pagination details to navigate through the list of records.'
          }
        }
      },
      servers: [
        {
          url: 'https://api.facet.org/v2'
        }
      ]
    }
  }
  
  contract_object = config.openapi_specs['v1/swagger.yaml'][:components][:schemas][:ContractObject]
  
  contract_properties = contract_object[:properties]
  
  state_addition = {
    current_state: {
      type: :object,
      additionalProperties: true,
      description: 'Current state of the contract. Includes variable values and other state-related information, present only in detailed contract information (show action).',
      example: { name: 'MyToken', symbol: 'MTK', decimals: 18, totalSupply: 1000000 }
    }
  }
  
  updated_properties = contract_properties.merge(state_addition)

  # Create a new component schema that includes the updated properties
  contract_with_state_component = contract_object.merge({
    type: contract_object[:type],
    properties: updated_properties
  })
  
  config.openapi_specs['v1/swagger.yaml'][:components][:schemas][:ContractObjectWithState] = contract_with_state_component

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
