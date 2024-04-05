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
        title: 'Facet API V1',
        version: 'v1',
        description: <<~DESC
        ## Overview
        This API allows for managing and retrieving information on blocks and transactions in a blockchain system. 
  
        Use this API to:
        - Retrieve lists of blocks and transactions
        - Fetch detailed information about specific blocks or transactions
        - Submit new transactions to the blockchain
  
        ## Authentication
        Most endpoints require authentication. Please refer to the authentication section for details on how to authenticate your requests.
        DESC
      },
      tags: [
        {
          name: 'Blocks',
          description: 'Operations related to blockchain blocks.'
        },
        {
          name: 'Transactions',
          description: 'Endpoints for transaction processing and retrieval.'
        }
        # Add more tags as needed
      ],
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
          PaginationObject: {
            type: :object,
            properties: {
              page_key: { type: :string, example: '18680069-4-1', description: 'Key for the next page of results. Supply this in the page_key query parameter to retrieve the next set of items.' },
              has_more: { type: :boolean, example: true, description: 'Indicates if more items are available beyond the current page.' }
            },
            description: 'Contains pagination details to navigate through the list of blocks.'
          }
        }
      },
      servers: [
        {
          url: 'https://api.facet.org'
        }
      ]
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
