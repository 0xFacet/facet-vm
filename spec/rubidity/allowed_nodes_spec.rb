require 'rails_helper'

RSpec.describe NodeChecker do
  def expect_raise(code = nil, &block)
    if !code
      code = block.source
      code = Unparser.parse(code).children.third.unparse
    end
    
    expect {
      ConstsToSends.process(code)
    }.to raise_error(NodeChecker::NodeNotAllowed)
  end
  
  def expect_not_raise(code = nil, &block)
    if !code
      code = block.source
      code = Unparser.parse(code).children.third.unparse
    end
    
    expect {
      ConstsToSends.process(code)
    }.not_to raise_error
  end
  
  it "disallows bad nodes" do
    expect_raise("__a__")
    expect_raise("instance_eval")
    
    expect_raise do
      @a = 'blah'
    end
    
    expect_raise do
      while true do
        puts "hi"
      end
    end

    expect_raise do
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa(1)
    end
    
    expect_raise do
      blah(:@true)
    end
    
    expect_raise do
      Class
    end
    
    expect_not_raise do
      contract :AddressArg do
        event :SayHi, { sender: :address }
        event :Responded, { response: :string }
        
        constructor(testAddress: :address) {
          emit :SayHi, sender: testAddress
        }
        
        function :respond, { greeting: :string }, :public do
          emit :Responded, response: (greeting + " back")
        end
      end
    end
    
  end
end
