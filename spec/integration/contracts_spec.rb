require 'swagger_helper'

describe 'Contracts API', doc: true do
  path '/contracts' do
    get 'List Contracts' do
      tags 'Contracts'
      operationId 'listContracts'
      produces 'application/json'
      description 'List all contracts, optionally filtered by init code hash.'
      
      parameter name: :init_code_hash,
                in: :query,
                type: :string,
                description: 'Filter contracts by their init code hash.',
                required: false
                
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter
      
      response '200', 'Contracts retrieved successfully' do
        schema type: :object,
          properties: {
            result: {
              type: :array,
              items: { '$ref' => '#/components/schemas/ContractObject' }
            },
            pagination: { '$ref' => '#/components/schemas/PaginationObject' }
          },
          description: 'Response body for a successful retrieval of contracts. `current_state` is not populated for this action.'

        run_test!
      end
    end
  end
  
  path '/contracts/{address}' do
    get 'Show Contract' do
      tags 'Contracts'
      operationId 'showContract'
      produces 'application/json'
      description 'Retrieves a single contract by its address, including the current state.'
  
      parameter name: :address,
                in: :path,
                type: :string,
                description: 'The address of the contract to retrieve.',
                required: true
  
      response '200', 'Contract retrieved successfully' do
        schema type: :object,
          properties: {
            result: { 
              '$ref' => '#/components/schemas/ContractObjectWithState' 
            }
          },
          description: 'Response body for a successful retrieval of a contract, including its current state.'
  
        run_test!
      end
  
      response '404', 'Contract not found' do
        schema type: :object,
              properties: {
                message: { type: :string, example: 'Requested record not found' }
              },
              description: 'Response body returned when no contract with the specified address exists.'
  
        run_test!
      end
    end
  end
  
  path '/contracts/{address}/static-call/{function}' do
    get 'Static Call' do
      tags 'Contracts'
      operationId 'staticCall'
      produces 'application/json'
      description <<~DESC
        Executes a read-only (static) call to a specified contract function. 
        This endpoint allows you to simulate contract function execution without 
        making any state changes to the blockchain.

        Provide function arguments as named arguments in the `args` parameter 
        (e.g., `{ "decimals": 18, "name": "Facet" }`), and any environmental settings 
        such as `msgSender` in the `env` parameter.
      DESC

      parameter name: :address,
                in: :path,
                type: :string,
                description: 'The contract address.',
                required: true

      parameter name: :function,
                in: :path,
                type: :string,
                description: 'The function name to call.',
                required: true

      parameter name: :args,
                in: :query,
                type: :string,
                description: 'JSON string of named arguments for the function call. Example: `{"decimals":18, "name": "Facet"}`',
                required: false

      parameter name: :env,
                in: :query,
                type: :string,
                description: 'JSON string of environmental settings such as `msgSender`. Example: `{"msgSender":"0x123..."}`',
                required: false

      response '200', 'Function executed successfully' do
        schema type: :object,
               properties: {
                 result: { type: :string, example: '29348', description: 'The result of the function call.' }
               },
               description: 'The result of the static call to the contract function.'

        run_test!
      end

      response '400', 'Bad request' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Invalid arguments', description: 'Error message describing what went wrong.' }
               },
               description: 'Response returned when the request is malformed or the arguments/env are invalid.'

        run_test!
      end
    end
  end
  
  path '/contracts/{address}/storage-get/{storage_key}' do
    get 'Get Storage Value' do
      tags 'Contracts'
      operationId 'getStorageValue'
      produces 'application/json'
      description <<~DESC
        Retrieves storage values directly from a specified contract. This endpoint allows you to query specific storage slots or mappings within a contract. Note:
        
        1. Return values are untyped; if a queried value does not exist, the result will be `null` rather than a type-specific default (e.g., `0` for `uint256`).
        
        2. Only direct contract storage values can be queried; interactions involving multiple contracts are not supported.

        Provide the storage key(s) as arguments in the request.
      DESC

      parameter name: :address,
                in: :path,
                type: :string,
                description: 'The contract address to query.',
                required: true

      parameter name: :storage_key,
                in: :path,
                type: :string,
                description: 'The primary key for the storage value.',
                required: true

      parameter name: :args,
                in: :query,
                type: :string,
                description: 'Additional keys for nested mappings or arrays, provided as a JSON array string. Example: `["0x123...", "0x456..."]`',
                required: false

      response '200', 'Storage value retrieved successfully' do
        schema type: :object,
               properties: {
                 result: { 
                   type: :string,
                   nullable: true,
                   example: '29348 or null',
                   description: 'The result of the storage query. Untyped and may be `null` if the value does not exist.'
                 }
               },
               description: 'The result of querying a storage value from the contract.'

        run_test!
      end

      response '400', 'Bad request' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Invalid args', description: 'Error message describing what went wrong, such as invalid arguments.' }
               },
               description: 'Response returned when the request is malformed or the provided arguments are invalid.'

        run_test!
      end
    end
  end
  
  path '/contracts/simulate' do
    get 'Simulate Transaction' do
      tags 'Contracts'
      operationId 'simulateTransaction'
      produces 'application/json'
      description <<~DESC
        Simulates a contract transaction to predict its outcome, including any errors, state changes, or effects on other contracts, without committing the transaction to the blockchain. 
        
        The transaction payload (`tx_payload`) should be JSON-encoded and included in the query string. It includes the operation type (`op`), data about the transaction such as the recipient address (`to`), function to call, and arguments for the function (`args`).
      DESC

      parameter name: :from,
                in: :query,
                type: :string,
                description: 'The Ethereum address initiating the transaction.',
                required: true

      parameter name: :tx_payload,
                in: :query,
                type: :string,
                description: 'JSON-encoded payload of the transaction to simulate, including operation, target contract, function, and arguments. Example: `{"op":"call","data":{"to":"0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e","function":"swapExactTokensForTokens","args":{"path":["0x1673540243e793b0e77c038d4a88448eff524dce","0x55ab0390a89fed8992e3affbf61d102490735e24"],"deadline":"1000000000000000000","to":"0xC2172a6315c1D7f6855768F843c420EbB36eDa97","amountIn":"1000000000000000000","amountOutMin":0}}}`',
                required: true,
                example: '{"op":"call","data":{"to":"0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e","function":"swapExactTokensForTokens","args":{"path":["0x1673540243e793b0e77c038d4a88448eff524dce","0x55ab0390a89fed8992e3affbf61d102490735e24"],"deadline":"1000000000000000000","to":"0xC2172a6315c1D7f6855768F843c420EbB36eDa97","amountIn":"1000000000000000000","amountOutMin":0}}}'

      response '200', 'Transaction simulated successfully' do
        schema type: :object,
               properties: {
                 result: { '$ref' => '#/components/schemas/SimulateTransactionResponse' }
               },
               description: 'The result of the simulated transaction, including any outcomes, errors, or state changes.'

        run_test!
      end

      response '500', 'Simulation error' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Simulation failed due to an internal error.' }
               },
               description: 'Error response when the simulation cannot be completed due to an error.'

        run_test!
      end
    end
  end
end
