class Contract < ApplicationRecord
  self.inheritance_column = :_type_disabled
  
  include ContractErrors
    
  has_many :call_receipts, primary_key: 'contract_id', class_name: "ContractCallReceipt", dependent: :destroy
  has_many :states, primary_key: 'contract_id', class_name: "ContractState", dependent: :destroy
  
  belongs_to :ethscription, primary_key: 'ethscription_id', foreign_key: 'contract_id',
    class_name: "Ethscription", touch: true
  
  attr_accessor :current_transaction
  attr_reader :implementation
  
  delegate :msg, to: :implementation
  
  def implementation
    @implementation ||= type.constantize.new(self)
  end
  
  def current_state
    states.newest_first.first || ContractState.new
  end
  
  def execute_function(function_name, function_args, persist_state:)
    begin
      with_state_management(persist_state: persist_state) do
        implementation.send(function_name.to_sym, function_args.deep_symbolize_keys)
      end
    rescue ContractError => e
      e.contract = self
      raise e
    end
  end
  
  def with_state_management(persist_state:)
    implementation.state_proxy.load(current_state.state.deep_dup)
    initial_state = implementation.state_proxy.serialize
    
    yield.tap do
      final_state = implementation.state_proxy.serialize
      
      if (final_state != initial_state) && persist_state
        states.create!(
          ethscription_id: current_transaction.ethscription.ethscription_id,
          state: final_state
        )
      end
    end
  end
  
  def self.all_abis(deployable_only: false)
    contract_classes = valid_contract_types

    contract_classes.each_with_object({}) do |name, hash|
      contract_class = "Contracts::#{name}".constantize

      next if deployable_only && contract_class.is_abstract_contract

      hash[contract_class.name] = contract_class.public_abi
    end.transform_keys(&:demodulize)
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :contract_id,
        ]
      )
    ).tap do |json|
      json['abi'] = implementation.public_abi.map do |name, func|
        [name, func.as_json.except('implementation')]
      end.to_h
      
      json['current_state'] = current_state.state
      json['current_state']['contract_type'] = type.demodulize
      
      klass = implementation.class
      tree = [klass, klass.linearized_parents].flatten
      
      json['source_code'] = tree.map do |k|
        {
          language: 'ruby',
          code: source_code(k)
        }
      end
    end
  end
  
  def self.valid_contract_types
    Contracts.constants.map do |c|
      Contracts.const_get(c).to_s.demodulize
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract_id: contract_id, 
      function_name: name, 
      function_args: args
    )
  end

  def source_file(type)
    ActiveSupport::Dependencies.autoload_paths.each do |base_folder|
      relative_path = "#{type.to_s.underscore}.rb"
      absolute_path = File.join(base_folder, relative_path)

      return absolute_path if File.file?(absolute_path)
    end
    nil
  end

  def source_code(type)
    File.read(source_file(type)) if source_file(type)
  end
end
