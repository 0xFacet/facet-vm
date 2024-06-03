require 'rails_helper'

RSpec.describe GasCounter, type: :model do
  let(:transaction_context) { double("TransactionContext", gas_limit: 10) }
  let(:gas_counter) { GasCounter.new(transaction_context) }

  before do
    stub_const("GasCounter::EVENT_TO_COST", {
      "ExternalContractCall" => 0.5,
      "UnknownEvent" => 0.01
    })
  end

  describe '#increment_gas' do
    it 'increments the gas used for an event' do
      gas_counter.increment_gas("ExternalContractCall")
      expect(gas_counter.per_event_gas_used["ExternalContractCall"][:gas_used]).to eq(0.5)
      expect(gas_counter.per_event_gas_used["ExternalContractCall"][:count]).to eq(1)
      expect(gas_counter.total_gas_used).to eq(0.5)
    end

    it 'increments the count for an event' do
      2.times { gas_counter.increment_gas("ExternalContractCall") }
      expect(gas_counter.per_event_gas_used["ExternalContractCall"][:count]).to eq(2)
      expect(gas_counter.total_gas_used).to eq(1.0)
    end

    it 'uses the default gas cost for unknown events' do
      gas_counter.increment_gas("UnknownEvent")
      expect(gas_counter.per_event_gas_used["UnknownEvent"][:gas_used]).to eq(0.01)
      expect(gas_counter.per_event_gas_used["UnknownEvent"][:count]).to eq(1)
      expect(gas_counter.total_gas_used).to eq(0.01)
    end
  end

  describe '#enforce_gas_limit!' do
    it 'raises an error if the gas limit is exceeded' do
      allow(transaction_context).to receive(:gas_limit).and_return(0.99)
      gas_counter.increment_gas("ExternalContractCall")
      expect { gas_counter.increment_gas("ExternalContractCall") }.to raise_error(
        ContractErrors::ContractError, "Gas limit exceeded"
      )
    end
  end
end
