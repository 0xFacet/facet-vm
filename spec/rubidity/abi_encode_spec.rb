require 'rails_helper'

describe 'toPackedBytes' do  
  dc = RubidityTranspiler.transpile_and_get("ERC20").build_class
  
  it 'correctly encodes uint32' do
    uint32 = TypedVariable.create(:uint32, 5)
    expect(uint32.toPackedBytes.value).to eq('0x00000005')
  end
  
  it 'handles strings' do
    variable = TypedVariable.create(:string, "Hello, world!")
    expect(variable.toPackedBytes.value).to eq("0x" + "Hello, world!".unpack1('H*'))
  end

  it 'handles addresses' do
    address = "0x" + "a" * 40
    variable = TypedVariable.create(:address, address)
    expect(variable.toPackedBytes.value).to eq(address)
  end

  it 'handles booleans' do
    variable = TypedVariable.create(:bool, true)
    expect(variable.toPackedBytes.value).to eq("0x01")

    variable = TypedVariable.create(:bool, false)
    expect(variable.toPackedBytes.value).to eq("0x00")
  end
  
  it 'correctly encodes contract types as addresses' do
    contract_address = "0xabcdef0123456789abcdef0123456789abcdef01"
    
    proxy = ::ContractVariable::Value.new(
      contract_class: dc,
      address: contract_address
    )
    
    contract_var = ::TypedVariable.create(:contract, proxy)
    
    packed = dc.new.send(:abi).encodePacked(contract_var)
    expected = contract_address
    expect(packed.value).to eq(expected)
  end  
  
  it 'correctly encodes an array of integers' do
    array = TypedVariable.create(
      Type.create(:array, value_type: :int32),
      [1, 2, 3]
    )
    
    packed = dc.new.send(:abi).encodePacked(array)
    expected = "0x" + [1, 2, 3].map { |n| n.to_s(16).rjust(8, '0') }.join
    expect(packed.value).to eq(expected)
  end  
  
  it 'concatenates byte strings' do
    variable1 = TypedVariable.create(:int8, -123)
    variable2 = TypedVariable.create(:string, "Hello, world!")
    
    packed = dc.new.send(:abi).encodePacked(variable1, variable2)
    expected = "0x" + variable1.toPackedBytes.value.sub(/\A0x/, '') + variable2.toPackedBytes.value.sub(/\A0x/, '')
    expect(packed.value).to eq(expected)
  end
  
  it 'correctly encodes a combination of types' do
    uint = TypedVariable.create(:int32, 1)
    str = TypedVariable.create(:string, "test")
    result = dc.new.send(:abi).encodePacked(uint, str)

    expected = "0x" + "00000001" + "test".unpack1('H*')
    expect(result.value).to eq(expected)
  end
end