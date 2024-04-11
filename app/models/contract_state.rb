class ContractState < ApplicationRecord
  self.inheritance_column = :_type_disabled
  
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  
  scope :newest_first, lambda {
    order_clause = column_names.include?('transaction_index') ?
    'block_number DESC, transaction_index DESC' : 'block_number DESC'
    order(Arel.sql(order_clause))
  }
  
  after_create :update_contract_on_create, unless: :using_postgres?
  # TODO: make re-org safe
  after_destroy :update_contract_on_destroy, unless: :using_postgres?
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :transaction_hash,
          :contract_address,
          :state,
        ]
      )
    )
  end
  
  def update_contract_on_create
    # TODO: do it all in SQL
    latest_state = ContractState.where(contract_address: contract_address)
                                .order(block_number: :desc)
                                .first

    contract.update!(
      current_state: latest_state.state,
      current_type: latest_state.type,
      current_init_code_hash: latest_state.init_code_hash
    )
  end

  def update_contract_on_destroy
    latest_state = ContractState.where(contract_address: contract_address)
                                .where.not(id: id)
                                .order(block_number: :desc)
                                .first

    if latest_state.present?
      contract.update!(
        current_state: latest_state.state,
        current_type: latest_state.type,
        current_init_code_hash: latest_state.init_code_hash,
      )
    else
      contract.update!(
        current_state: {},
        current_type: nil,
        current_init_code_hash: nil,
      )
    end
  end
end
