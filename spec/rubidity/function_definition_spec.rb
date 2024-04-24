require 'rails_helper'

RSpec.describe ContractAstValidator do
  def get_def(ruby)
    ContractAstValidator::FunctionDefinition.new(ruby)
  end
  
  it "parses" do
    ruby = <<~RUBY
    function :transfer, { to: :address, amount: :uint256 }, :public, :virtual, returns: :bool do
      require(s.balanceOf[msg.sender] >= amount, "Insufficient balance")
      
      s.balanceOf[msg.sender] -= amount
      s.balanceOf[to] += amount
  
      emit :Transfer, from: msg.sender, to: to, amount: amount
      
      return true
    end
    RUBY

    function_definition = ContractAstValidator::FunctionDefinition.new(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:transfer)
    expect(function_definition.params).to eq({ to: :address, amount: :uint256 })
    
    ruby = <<~RUBY
      constructor(name: :string, symbol: :string, decimals: :uint8) {
        s.name = name
        s.symbol = symbol
        s.decimals = decimals
      }
    RUBY

    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:constructor)
    expect(function_definition.params).to eq({ name: :string, symbol: :string, decimals: :uint8 })
    
    ruby = <<~RUBY
    function(:add) do
    end
    RUBY

    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:add)
    expect(function_definition.params).to eq({})
    
    ruby = <<~RUBY
    function(:add, {a: :uint256, b: :uint256}) do
    end
    RUBY

    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:add)
    expect(function_definition.params).to eq({a: :uint256, b: :uint256})
    
    ruby = <<~RUBY
    constructor(name: :string) {
      a + b
    }
    RUBY

    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:constructor)
    expect(function_definition.params).to eq({name: :string})
    
    ruby = <<~RUBY
    constructor() { }
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:constructor)
    expect(function_definition.params).to eq({})
    
    ruby = <<~RUBY
      function(:noop, {}) { }
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:noop)
    expect(function_definition.params).to eq({})
    
    ruby = <<~RUBY
      function(:hi, {arg: :val}, :public, :view, returns: :string) do
        1 + 2
      end
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:hi)
    expect(function_definition.params).to eq({})
    
    ruby = <<~RUBY
    function(:feeTo, :external, :view, returns: :address)
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(true)
    expect(function_definition.name).to eq(:feeTo)
    expect(function_definition.params).to eq({})
    
    ruby = <<~RUBY
      function({}) { }
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(false)
    
    ruby = <<~RUBY
    def hi
      puts 'hello'
    end
    RUBY
  
    function_definition = get_def(ruby)
    expect(function_definition.valid?).to eq(false)
  end
end

