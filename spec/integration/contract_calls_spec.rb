require 'swagger_helper'

describe 'Contract Calls API' do
  path '/contract_calls' do
    get 'List Contract Calls' do
      tags 'Contract Calls'
      operationId 'listContractCalls'
      produces 'application/json'
      description 'List all contract calls, with optional filters for transaction hash, effective contract address, or to/from address.'
      
      parameter name: :transaction_hash,
                in: :query,
                type: :string,
                description: 'Filter by the transaction hash.',
                required: false
                
      parameter name: :effective_contract_address,
                in: :query,
                type: :string,
                description: 'Filter by the effective contract address.',
                required: false
                
      parameter name: :to_or_from,
                in: :query,
                type: :string,
                description: 'Filter by addresses that are either the sender or the effective contract address.',
                required: false
                
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter

      response '200', 'Contract Calls retrieved successfully' do
        schema type: :object,
          properties: {
            result: {
              type: :array,
              items: { '$ref' => '#/components/schemas/ContractCallObject' }
            },
            pagination: { '$ref' => '#/components/schemas/PaginationObject' }
          },
          description: 'Response body for a successful retrieval of contract calls. Includes an array of contract calls and pagination details.'

        run_test!
      end
    end
  end
end
