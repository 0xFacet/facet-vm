class ContractCallReceipt < ApplicationRecord
  belongs_to :contract, primary_key: 'contract_id', touch: true, optional: true
    
    belongs_to :created_by_ethscription,
      primary_key: 'ethscription_id', foreign_key: 'ethscription_id',
      class_name: "Ethscription", touch: true

end
