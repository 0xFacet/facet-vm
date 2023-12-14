class DeployHelper
  def self.params_to_uri(type: nil, op:, data:)
    mimetype = type == 'system' ? SystemConfigVersion.system_mimetype :
      ContractTransaction.transaction_mimetype
      
    payload = {
      op: op,
      data: data
    }
      
    %{data:#{mimetype};rule=esip6,#{payload.to_json}}
  end
  
  def self.variable_fee_deploy2(
    router_address: "0xf29e6e319ac4ce8c100cfc02b1702eb3d275029e"
  )
    ordered_ethscriptions = []
      
    supported_contracts = [
      "EtherBridge",
      "EthscriptionERC20Bridge",
      "PublicMintERC20",
      "NameRegistry",
      "FacetSwapV1Factory02",
      "FacetSwapV1Pair02",
      "FacetSwapV1Router03",
      "AirdropERC20",
    ]
    
    supported_contracts = supported_contracts.map do |name|
      item = RubidityTranspiler.transpile_and_get(name)
      [
        name,
        OpenStruct.new(
          init_code_hash: item.init_code_hash,
          source_code: item.source_code
        )
      ]
    end.to_h
    
    ordered_ethscriptions << params_to_uri(
      type: 'system',
      op: 'updateSupportedContracts',
      data: supported_contracts.values.map(&:init_code_hash)
    )
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: router_address,
        function: "upgrade",
        args: {
          newHash: supported_contracts["FacetSwapV1Router03"].init_code_hash,
          newSource: supported_contracts["FacetSwapV1Router03"].source_code,
        }
      }
    )
  end
  
  def self.variable_fee_deploy(
    gnosis_safe:,
    router_address:,
    factory_address:,
    factory_pairs:
  )
    ordered_ethscriptions = []
    
    supported_contracts = [
      "EtherBridge",
      "EthscriptionERC20Bridge",
      "PublicMintERC20",
      "NameRegistry",
      "FacetSwapV1Factory02",
      "FacetSwapV1Pair02",
      "FacetSwapV1Router02",
      "AirdropERC20",
    ]
    
    supported_contracts = supported_contracts.map do |name|
      item = RubidityTranspiler.transpile_and_get(name)
      [
        name,
        OpenStruct.new(
          init_code_hash: item.init_code_hash,
          source_code: item.source_code
        )
      ]
    end.to_h
    
    ordered_ethscriptions << params_to_uri(
      type: 'system',
      op: 'updateSupportedContracts',
      data: supported_contracts.values.map(&:init_code_hash)
    )
    
    routerMigrationCalldata = {
      function: "onUpgrade",
      args: {
        owner: gnosis_safe,
        initialPauseState: true
      }
    }
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: router_address,
        function: "upgradeAndCall",
        args: {
          newHash: supported_contracts["FacetSwapV1Router02"].init_code_hash,
          newSource: supported_contracts["FacetSwapV1Router02"].source_code,
          migrationCalldata: routerMigrationCalldata.to_json
        }
      }
    )
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: factory_address,
        function: "upgrade",
        args: {
          newHash: supported_contracts["FacetSwapV1Factory02"].init_code_hash,
          newSource: supported_contracts["FacetSwapV1Factory02"].source_code,
        }
      }
    )
    
    pair_slices = factory_pairs.each_slice(10).to_a
    
    pair_slices.each.with_index do |slice, idx|
      source_to_use = idx == 0 ?
      supported_contracts["FacetSwapV1Pair02"].source_code : ""
      
      ordered_ethscriptions << params_to_uri(
        op: 'call',
        data: {
          to: factory_address,
          function: "upgradePairs",
          args: {
            pairs: slice,
            newHash: supported_contracts["FacetSwapV1Pair02"].init_code_hash,
            newSource: source_to_use,
          }
        }
      )
    end
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: factory_address,
        function: "setLpFeeBPS",
        args: 100
      }
    )
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: router_address,
        function: "updateProtocolFee",
        args: 30
      }
    )
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: router_address,
        function: "unpause"
      }
    )
    
    ordered_ethscriptions << params_to_uri(
      op: 'call',
      data: {
        to: router_address,
        function: "withdrawFees",
        args: gnosis_safe
      }
    )
    
    ordered_ethscriptions
  end
end
