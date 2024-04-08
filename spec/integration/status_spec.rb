# spec/integration/status_spec.rb
require 'swagger_helper'

describe 'Status API' do
  path '/vm_status' do
    get 'VM Status' do
      tags 'Status'
      operationId 'getVmStatus'
      produces 'application/json'
      description <<~DESC
        Retrieves the current status of the Virtual Machine (VM), including:
        - The number of ethscriptions behind the current block
        - The current block number being processed
        - The maximum block number processed
        - The number of blocks behind
        - The count of pending blocks
        - Overall core indexer status
      DESC

      response '200', 'VM status retrieved successfully' do
        schema type: :object,
               properties: {
                 ethscriptions_behind: { type: :integer, example: 10, description: 'Total newer ethscriptions behind the current block.' },
                 current_block_number: { type: :integer, example: 100, description: 'Current block number being processed.' },
                 max_processed_block_number: { type: :integer, example: 95, description: 'Maximum block number that has been processed.' },
                 blocks_behind: { type: :integer, example: 5, description: 'Number of blocks the system is behind the current block number.' },
                 pending_block_count: { type: :integer, example: 3, description: 'Count of blocks that are pending processing.' },
                 core_indexer_status: { 
                   type: :object,
                   additionalProperties: true,
                   description: 'Detailed status of the core indexer, structure varies depending on the indexer status.'
                 }
               },
               description: 'Provides various status indicators of the VM or indexer.'

        run_test!
      end
    end
  end
end
