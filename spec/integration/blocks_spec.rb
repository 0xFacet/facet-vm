# spec/integration/blocks_spec.rb
require 'swagger_helper'

describe 'Blocks API' do

  path '/blocks' do
    get 'List Blocks' do
      tags 'Blocks'
      operationId 'getBlocks'
      produces 'application/json'
      description 'List all Ethereum Blocks known by the VM.'
      
      parameter name: :sort_by, 
                in: :query, 
                type: :string, 
                description: 'Defines the order of the blocks to be returned. Can be either "newest_first" (default) or "oldest_first".',
                enum: ['newest_first', 'oldest_first'],
                required: false,
                default: 'newest_first'
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter

      response '200', 'Blocks retrieved successfully' do
        schema type: :object,
          properties: {
            result: {
              type: :array,
              items: { '$ref' => '#/components/schemas/BlockObject' }
            },
            pagination: { '$ref' => '#/components/schemas/PaginationObject' }
          },
          description: 'Response body for a successful retrieval of blocks. Includes an array of blocks and pagination details.'

        run_test!
      end
    end
  end
  
  path '/blocks/{id}' do

    get 'Get Block' do
      tags 'Blocks'
      operationId 'getBlock'
      produces 'application/json'
      description 'Retrieves a single Ethereum Block by its block number.'
      
      parameter name: :block_number, 
                in: :path, 
                type: :string, 
                description: 'The block number of the Ethereum Block to retrieve.',
                required: true
  
      response '200', 'Block retrieved successfully' do
        schema type: :object,
          properties: {
            result: { '$ref' => '#/components/schemas/BlockObject' }
          },
          description: 'Response body for a successful retrieval of a single block. Includes the details of the block.'
  
        run_test!
      end
  
      response '404', 'Block not found' do
        schema type: :object,
              properties: {
                message: { type: :string, example: 'Requested record not found' }
              },
              description: 'Response body returned when no block with the specified block number exists.'
  
        run_test!
      end
    end
  
  end
end
