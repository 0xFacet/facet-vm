# spec/rubidity_interpreter_spec.rb

require 'rails_helper'

RSpec.describe RubidityInterpreter, type: :module do
  describe '.build_implementation_instance_from_code_string' do
    let(:code_string) do
      code_string = <<~RUBY
        contract StubERC20New do
          event :Hi, { name: :string }
          
          constructor(name: :string) {
            # ERC20.constructor(name: name, symbol: "symbol", decimals: 18)
            emit :Hi, name: name
          }
          
          function :sayHi, :public, returns: :string do
            "Hi"
          end
          
          function :sayName, :public, returns: :string do
            ERC20(address(this)).name()
          end
        end
      
      RUBY
    end

    it 'returns an instance' do
      deploy_receipt = nil
      
      deploy_receipt = trigger_contract_interaction_and_expect_success(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        payload: {
          to: nil,
          data: {
            type: "PublicMintERC20New",
            args: {
              name: "Token1",
              symbol: "TK1",
              maxSupply: 21e24.to_d.to_i,
              perMintLimit: 21e24.to_d.to_i,
              decimals: 18
            }
          }
        }
      )

      pp deploy_receipt
      
      # context = MockTransactionContext.new(
      #   msg_sender: '0xC2172a6315c1D7f6855768F843c420EbB36eDa97',
      #   current_address: '0xC2172a6315c1D7f6855768F843c420EbB36eDa97',

      # )
      
      # TransactionContext.set(
      #   call_stack: CallStack.new,
      #   current_transaction: "0xA5EFE121819cD86BE6F168a2Cf745b299417520A",
      #   tx_origin: '0xC2172a6315c1D7f6855768F843c420EbB36eDa97',
      #   block_number: 1,
      #   block_timestamp: Time.zone.now.to_i,
      #   block_blockhash: "0x" + SecureRandom.hex(32),
      #   transaction_hash: "0x39a0dd1ec2c853a336967fa05f5cc47c88a10733c7443d9e9ac4d957494e6208",
      #   transaction_index: 2,
      #   ethscription: Ethscription.new,
      #   # mock_current_contract: Contract.new(
      #   #   address: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      #   # )
      # ) do
      #   klass = RubidityInterpreter.build_implementation_class_from_code_string(code_string)
      #   # binding.pry
      #   result = klass.new#(current_context: context)
        
      #   result.attach_contract_record("0xC2172a6315c1D7f6855768F843c420EbB36eDa97")
        
      #   expect(result.sayHi).to eq("hi!")
      #   expect(result.reportAddress).to eq("0xC2172a6315c1D7f6855768F843c420EbB36eDa97")
      #   expect(result.reportSender).to eq(context.msg.sender)
      #   expect(result.hum).to eq("hmmmm")
      # end
      

    end
  end
end
