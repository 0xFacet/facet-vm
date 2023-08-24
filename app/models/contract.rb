class Contract < ApplicationRecord
  has_many :call_receipts, primary_key: 'contract_id', class_name: "ContractCallReceipt", dependent: :destroy
  has_many :states, primary_key: 'contract_id', class_name: "ContractState", dependent: :destroy
  
  belongs_to :created_by_ethscription, primary_key: 'ethscription_id', foreign_key: 'contract_id',
    class_name: "Ethscription", touch: true
end
