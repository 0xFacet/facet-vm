require 'rails_helper'

RSpec.describe "ContractArtifact Creation" do
  let(:store_context) do
      Class.new do
        class << self
          attr_accessor :artifacts, :receipt

        def artifacts
          @artifacts ||= {}
        end
        
        def reset_artifacts
          @artifacts = {}
        end

        def add_contract_artifact(artifact)
          artifacts[artifact.init_code_hash] = artifact
        end
        
        def save_all
          to_import = artifacts.values.select(&:new_record?)
          
          to_import.each do |artifact|
            artifact.transaction_hash = receipt.transaction_hash
            artifact.block_number = receipt.block_number
            artifact.transaction_index = receipt.transaction_index
          end
          
          ContractArtifact.import!(to_import, on_duplicate_key_ignore: true)
          
          ContractDependency.import!(
            to_import.flat_map(&:contract_dependencies).select(&:new_record?),
            on_duplicate_key_ignore: true
          )
          
          reset_artifacts
        end
      end
    end
  end

  before(:each) do
    update_supported_contracts(
      'StubERC20'
    )
    
    store_context.receipt = trigger_contract_interaction_and_expect_success(
      from: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      payload: {
        to: nil,
        data: {
          type: "StubERC20",
          args: { name: "Token B" }
        }
      }
    )
    
    store_context.artifacts = {}
  end
  
  after(:each) do
    EthBlock.delete_all
  end
  
  describe '.parse_and_store' do
    let(:json_data) do
      RubidityTranspiler.new("StubERC721").generate_contract_artifact
    end

    before do
      ContractArtifact.parse_and_store(json_data, store_context)
    end

    it 'parses and stores the artifacts' do
      expect(store_context.artifacts.size).to eq(3)
    end

    it 'calculates the init_code_hash and execution_source_code for each artifact' do
      store_context.artifacts.values.each do |artifact|
        expect(artifact.init_code_hash).to be_present
        expect(artifact.execution_source_code).to be_present
      end
    end

    it 'stores dependencies in the correct order' do
      main_contract = store_context.artifacts.values.find { |artifact| artifact.name == 'StubERC721' }
      expect(main_contract.dependencies.size).to eq(2)
      expect(main_contract.dependencies[0].name).to eq('ERC721')
      expect(main_contract.dependencies[1].name).to eq('ERC2981')
    end
  end

  describe '.save_all' do
    let(:json_data) do
      RubidityTranspiler.new("StubERC721").generate_contract_artifact
    end

    before do
      ContractArtifact.parse_and_store(json_data, store_context)
      store_context.artifacts.values.each do |artifact|
        artifact.transaction_hash = "0x" + SecureRandom.hex(32)
        artifact.block_number = rand(1..1000000)
        artifact.transaction_index = rand(1..1000000)
      end
      store_context.save_all
    end

    it 'saves all artifacts to the database' do
      expect(ContractArtifact.count).to eq(5)
    end

    it 'saves the correct attributes' do
      main_contract = ContractArtifact.find_by(name: 'StubERC721')
      expect(main_contract).to be_present
      expect(main_contract.init_code_hash).to be_present
      expect(main_contract.execution_source_code).to be_present
    end

    it 'saves the dependencies with the correct order' do
      main_contract = ContractArtifact.find_by(name: 'StubERC721')
      expect(main_contract.dependencies.size).to eq(2)
      expect(main_contract.dependencies[0].name).to eq('ERC721')
      expect(main_contract.dependencies[1].name).to eq('ERC2981')
    end
  end
end
