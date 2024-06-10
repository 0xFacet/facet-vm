require 'rails_helper'

RSpec.describe UltraMinimalProxy do
  let(:owner_address) { "0x000000000000000000000000000000000000000a" }

  before do
    update_supported_contracts("DangerousContract")
  end
  
  describe ".execute_user_code_on_context" do
    module StoragePointerTestExtensions
      def self.prepended(base)
        class << base
          attr_accessor :private_val
        end
      end

      def dangerousMethod
        self.class.private_val = 10
      end
      
      def dangerousMethod=(value)
        self.class.private_val = value
      end

      def self.private_val
        @private_val
      end
      
      def self.private_val=(value)
        @private_val = value
      end
    end

    before do
      StoragePointer.singleton_class.prepend(StoragePointerTestExtensions)
      StoragePointer.prepend(StoragePointerTestExtensions)
      StoragePointer.private_val = 100
    end
    
    it "does things" do
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          op: :create,
          data: {
            type: "DangerousContract"
          }
        }
      )
      
      expect(StoragePointer.private_val).to eq(100)
    end
  end
end
