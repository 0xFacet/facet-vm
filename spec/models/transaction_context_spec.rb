RSpec.describe TransactionContext do
  before do
    TransactionContext.reset
  end
  
  describe '#current_transaction=' do
    it 'sets the current_transaction if not already set' do
      tx = double('ContractTransaction')
      expect { TransactionContext.current_transaction = tx }.not_to raise_error
      expect(TransactionContext.current_transaction).to eq(tx)
    end

    it 'raises an error if current_transaction is already set' do
      tx1 = double('ContractTransaction')
      tx2 = double('ContractTransaction')
      TransactionContext.current_transaction = tx1
      expect { TransactionContext.current_transaction = tx2 }.to raise_error("current_transaction is already set")
    end
  end

  describe '#msg_sender=' do
    let(:initial_caller_address) {
      TypedVariable.create(:address, '0xC2172a6315c1D7f6855768F843c420EbB36eDa97')
    }
    
    let(:inner_caller_address) {
      TypedVariable.create(:address, '0x11172a6315c1D7f6855768F843c420EbB36eD111')
    }
    
    it 'sets and resets msg_sender and msg.sender' do
      tx = ContractTransaction.new
      TransactionContext.current_transaction = tx
      TransactionContext.msg_sender = initial_caller_address
      
      expect(TransactionContext.msg.sender).to eq(initial_caller_address)
      expect(TransactionContext.msg_sender).to eq(initial_caller_address)
      
      TransactionContext.set(msg_sender: inner_caller_address) do
        expect(TransactionContext.msg_sender).to eq(inner_caller_address)
        expect(TransactionContext.msg.sender).to eq(inner_caller_address)
      end
      
      expect(TransactionContext.msg_sender).to eq(initial_caller_address)
      expect(TransactionContext.msg.sender).to eq(initial_caller_address)
    end
    
    it "correctly sets and resets msg_sender and msg.sender" do
      tx = ContractTransaction.new
      TransactionContext.current_transaction = tx
      TransactionContext.msg_sender = initial_caller_address
      
      TransactionContext.set(msg_sender: inner_caller_address) do
        expect(TransactionContext.msg_sender).to eq(inner_caller_address)
        expect(TransactionContext.msg.sender).to eq(inner_caller_address)
      end

      expect(TransactionContext.msg_sender).to eq(initial_caller_address)
      expect(TransactionContext.msg.sender).to eq(initial_caller_address)
    end
  end

  context 'when current_transaction is not set' do
    it 'raises error on accessing msg' do
      expect { TransactionContext.msg }.to raise_error('current_transaction is not set')
    end
  
    it 'raises error on accessing tx' do
      expect { TransactionContext.tx }.to raise_error('current_transaction is not set')
    end
  
    it 'raises error on accessing block' do
      expect { TransactionContext.block }.to raise_error('current_transaction is not set')
    end
  end
  
  describe 'delegated methods' do
    let(:tx) { double('ContractTransaction') }
    
    before do
      TransactionContext.current_transaction = tx
    end
    
    it 'raises an error if no current transaction is set' do
      TransactionContext.current_transaction = nil
      expect { TransactionContext.msg }.to raise_error("current_transaction is not set")
    end
  end
end
