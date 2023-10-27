pragma :rubidity, "1.0.0"

contract :Upgradeable, abstract: true do
  address :public, :upgradeAdmin
  
  event :ContractUpgraded, { oldHash: :bytes32, newHash: :bytes32 }
  event :UpgradeAdminChanged, { newUpgradeAdmin: :address }
  
  constructor(upgradeAdmin: :address) {
    s.upgradeAdmin = upgradeAdmin
  }
  
  function :setUpgradeAdmin, { newUpgradeAdmin: :address }, :public do
    require(msg.sender == s.upgradeAdmin, "NOT_AUTHORIZED")
    
    s.upgradeAdmin = newUpgradeAdmin
    
    emit :UpgradeAdminChanged, newUpgradeAdmin: newUpgradeAdmin
  end
  
  function :upgradeAndCall, { newHash: :bytes32, migrationCalldata: :string }, :public do
    upgrade(newHash: newHash)

    (success, data) = address(this).call(migrationCalldata)
    require(success, "Migration failed")
  end
  
  function :upgrade, { newHash: :bytes32 }, :public do
    currentHash = esc.getImplementationHash
    
    require(msg.sender == s.upgradeAdmin, "NOT_AUTHORIZED")
    
    esc.upgradeContract(newHash)
    
    emit :ContractUpgraded, oldHash: currentHash, newHash: newHash
  end
end
