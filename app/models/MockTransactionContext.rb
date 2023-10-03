class MockTransactionContext < ActiveSupport::CurrentAttributes

  # The attributes are now instance variables instead of class-level attributes.
  attr_accessor :call_stack, :ethscription, :current_call, :current_address,
                :transaction_hash, :transaction_index, :current_transaction, 
                :block_number, :block_timestamp, :block_blockhash,
                :msg_sender, :tx_origin

  # A simple initializer where you can pass the initial state of the context.
  def initialize(attributes = {})
    attributes.each do |k, v|
      instance_variable_set("@#{k}", v)
    end
  end

  def msg
    Struct.new(:sender).new(msg_sender)
  end

  def tx
    Struct.new(:origin).new(tx_origin)
  end

  def block
    Struct.new(:number, :timestamp, :blockhash).new(block_number, block_timestamp, block_blockhash)
  end
  
  def log_event(event)
  end
end
