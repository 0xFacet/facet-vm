# spec/integration/transactions_spec.rb
require 'swagger_helper'

describe 'Transactions API', doc: true do
  path '/transactions' do
    get 'List Transactions' do
      tags 'Transactions'
      operationId 'listTransactions'
      produces 'application/json'
      description 'Lists transactions (transaction receipts) with optional filtering parameters.'

      parameter name: :block_number,
                in: :query,
                type: :integer,
                description: 'Filter transactions by block number.',
                required: false

      parameter name: :from,
                in: :query,
                type: :string,
                description: 'Filter transactions by the sender address.',
                required: false

      parameter name: :to,
                in: :query,
                type: :string,
                description: 'Filter transactions by the effective contract address (recipient).',
                required: false

      parameter name: :to_or_from,
                in: :query,
                type: :string,
                description: 'Filter transactions involving the specified address either as sender or recipient.',
                required: false

      parameter name: :after_block,
                in: :query,
                type: :integer,
                description: 'Filter transactions occurring after the specified block number.',
                required: false
      
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter
      
      response '200', 'Transactions retrieved successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :array,
                   items: { '$ref' => '#/components/schemas/TransactionObject' }
                 },
                 pagination: { '$ref' => '#/components/schemas/PaginationObject' }
               },
               description: 'A list of transactions (transaction receipts) matching the filter criteria, if any, along with pagination details.'

        run_test!
      end
    end
  end
  
  path '/transactions/{transaction_hash}' do
    get 'Show Transaction' do
      tags 'Transactions'
      operationId 'showTransaction'
      produces 'application/json'
      description 'Retrieves details of a single transaction by its hash.'

      parameter name: :transaction_hash,
                in: :path,
                type: :string,
                description: 'The hash of the transaction to retrieve.',
                required: true

      response '200', 'Transaction retrieved successfully' do
        schema type: :object,
               properties: {
                 result: { '$ref' => '#/components/schemas/TransactionObject' }
               },
               description: 'The details of the transaction, represented as a transaction receipt.'

        run_test!
      end

      response '404', 'Transaction not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Transaction not found' }
               },
               description: 'Response returned when no transaction with the specified hash exists.'

        run_test!
      end
    end
  end
end
