# spec/integration/status_spec.rb
require 'swagger_helper'

describe 'Status API', doc: true do
  path '/vm_status' do
    get 'VM Status' do
      tags 'Status'
      operationId 'getVmStatus'
      produces 'application/json'
      description <<~DESC
        Retrieves the current status of the Virtual Machine (VM)
      DESC

      response '200', 'VM status retrieved successfully' do
        schema type: :object,
               properties: {
                 ethscriptions_behind: { type: :string, example: "10", description: 'Number of ethscriptions remaining to be processed.' },
                 current_block_number: { type: :string, example: "100", description: 'Current Ethereum block number.' },
                 max_processed_block_number: { type: :string, example: "95", description: 'Maximum block number that has been processed.' },
                 blocks_behind: { type: :string, example: "5", description: 'Number of blocks the VM is behind.' },
                 pending_block_count: { type: :string, example: "3", description: 'Count of blocks that are pending processing.' },
                 core_indexer_status: { 
                   type: :object,
                   description: 'Detailed status of the core indexer, structure varies depending on the indexer status.',
                   example: {
                    "last_imported_block": "19618604",
                    "blocks_behind": "0"
                  }
                 }
               },
               description: 'Provides various status indicators of the VM or indexer.'

        run_test!
      end
    end
  end
end
