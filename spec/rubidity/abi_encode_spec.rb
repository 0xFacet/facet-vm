require 'rails_helper'

describe 'toPackedBytes' do
  class TypedVariable
    def unwrap
      self
    end
  end
  
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

  it 'correctly encodes large integers' do
    large_num = TypedVariable.create(:uint256, 2**256 - 1)
    packed = dc.new.abi_encodePacked(large_num)
    expected = "0x" + ("f" * 64)
    expect(packed.value).to eq(expected)
  end
  
  it 'raises an error when trying to encode an empty byte string' do
    empty_bytes = TypedVariable.create(:bytes)
    empty_string = TypedVariable.create(:string)
  
    expect { 
      var = dc.new.abi_encodePacked(empty_bytes, empty_string)
    }.to raise_error("Can't encode empty bytes")
  end  
  
  it 'correctly encodes zero values' do
    zero_int = TypedVariable.create(:int32, 0)
    packed = dc.new.abi_encodePacked(zero_int).unwrap
    expect(packed.value).to eq("0x00000000")
  end  
  
  it 'correctly encodes mixed data types' do
    int_var = TypedVariable.create(:int32, 1)
    string_var = TypedVariable.create(:string, "test")
    address_var = TypedVariable.create(:address, "0x123456789abcdef0123456789abcdef012345679")
    packed = dc.new.abi_encodePacked(int_var, string_var, address_var).unwrap
    expected = "0x00000001" + "test".unpack1('H*') + "123456789abcdef0123456789abcdef012345679"
    expect(packed.value).to eq(expected)
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
    
    packed = dc.new.abi_encodePacked(contract_var).unwrap
    expected = contract_address
    expect(packed.value).to eq(expected)
  end  
  
  it 'correctly encodes an array of integers' do
    array = TypedVariable.create(
      Type.create(:array, value_type: :int32),
      [1, 2, 3]
    )
    
    packed = dc.new.abi_encodePacked(array).unwrap
    expected = "0x" + [1, 2, 3].map { |n| n.to_s(16).rjust(8, '0') }.join
    expect(packed.value).to eq(expected)
  end  
  
  it 'concatenates byte strings' do
    variable1 = TypedVariable.create(:int8, -123)
    variable2 = TypedVariable.create(:string, "Hello, world!")
    
    packed = dc.new.abi_encodePacked(variable1, variable2).unwrap
    expected = "0x" + variable1.toPackedBytes.value.sub(/\A0x/, '') + variable2.toPackedBytes.value.sub(/\A0x/, '')
    expect(packed.value).to eq(expected)
  end
  
  it 'correctly encodes a combination of types' do
    uint = TypedVariable.create(:int32, 1)
    str = TypedVariable.create(:string, "test")
    result = dc.new.abi_encodePacked(uint, str).unwrap

    expected = "0x" + "00000001" + "test".unpack1('H*')
    expect(result.value).to eq(expected)
  end
end