require 'rails_helper'

class Contracts::ERC20LiquidityPool < ContractImplementation
  address :public, :token0
  address :public, :token1

  constructor(token0: :address, token1: :address) do
    s.token0 = token0
    s.token1 = token1
  end

  function :addLiquidity, {token0Amount: :uint256, token1Amount: :uint256}, :public, returns: :bool do
    ERC20(s.token0).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token0Amount
    )

    ERC20(s.token1).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token1Amount
    )
  end

  function :reserves, {}, :public, :view, returns: { token0: :uint256, token1: :uint256 } do
    return {
      token0: ERC20(s.token0).balanceOf(address(this)),
      token1: ERC20(s.token1).balanceOf(address(this))
    }
  end

  function :calculateOutputAmount, {
    inputToken: :address,
    outputToken: :address,
    inputAmount: :uint256
  }, :public, :view, returns: :uint256 do
    inputReserve = ERC20(inputToken).balanceOf(address(this))
    outputReserve = ERC20(outputToken).balanceOf(address(this))

    ((inputAmount * outputReserve) / (inputReserve + inputAmount)).to_i
  end

  function :swap, {
    inputToken: :address,
    outputToken: :address,
    inputAmount: :uint256
  }, :public, returns: :uint256 do
    require([s.token0, s.token1].include?(inputToken), "Invalid input token")
    require([s.token0, s.token1].include?(outputToken), "Invalid output token")

    require(inputToken != outputToken, "Input and output tokens can't be the same")

    outputAmount = calculateOutputAmount(
      inputToken: inputToken,
      outputToken: outputToken,
      inputAmount: inputAmount
    )

    outputReserve = ERC20(outputToken).balanceOf(address(this))

    require(outputAmount <= outputReserve, "Insufficient output reserve")

    ERC20(inputToken).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: inputAmount
    )

    ERC20(outputToken).transfer(
      msg.sender,
      outputAmount
    )

    return outputAmount
  end
end

RSpec.describe Contract, type: :model do
  before do
    ENV['INDEXER_API_BASE_URI'] = "http://goerli-api.ethscriptions.com/api"
    
    @creation_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "PublicMintERC20",
        "constructorArgs": {
          "name": "My Fun Token",
          "symbol": "FUN",
          "maxSupply": "21000000",
          "perMintLimit": "1000",
          "decimals": 18
        },
      }
    )
  end

  describe ".call_contract_from_ethscription_if_needed!" do
    before do
      @mint_receipt = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": @creation_receipt.address,
          "functionName": "mint",
          "args": ["5"],
        }
      )
    end
    
    it "won't call constructor after deployed" do
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": @creation_receipt.address,
          "functionName": "constructor",
          "args": {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      )
    end
    
    it "will simulate a deploy transaction" do
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        to: nil,
        data: {
          type: "PublicMintERC20",
          args: {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          }
        }
      }
      
      expect {
        receipt = ContractTransaction.simulate_transaction(from: from, tx_payload: data)
    
        expect(receipt).to be_a(ContractTransactionReceipt)
        expect(receipt.status).to eq("success")
        expect(Ethscription.find_by(ethscription_id: receipt.transaction_hash)).to be_nil
        
      }.to_not change {
        [Contract, ContractState, Ethscription].map{|i| i.all.cache_key_with_version}
      }
    end
    
    it "will simulate a call to a deployed contract" do
      deploy_receipt = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "PublicMintERC20",
          "constructorArgs": {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      )
    
      call_receipt_success = ContractTransaction.simulate_transaction(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        tx_payload: {
          "to": deploy_receipt.address,
          data: {
            "function": "mint",
            "args": {
              "amount": "5"
            }
          }
        }
      )
    
      expect(call_receipt_success).to be_a(ContractTransactionReceipt)
      expect(call_receipt_success.status).to eq("success")
      
      expect(Ethscription.find_by(ethscription_id: call_receipt_success.transaction_hash)).to be_nil
      
      call_receipt_fail = ContractTransaction.simulate_transaction(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        tx_payload: {
          "to": deploy_receipt.address,
          data: {
            "function": "mint",
            "args": {
              "amount": "5000"
            },
          }
        }
      )
      
      expect(call_receipt_fail).to be_a(ContractTransactionReceipt)
      expect(call_receipt_fail.status).to eq("error")
      
      expect(Ethscription.find_by(ethscription_id: call_receipt_fail.transaction_hash)).to be_nil
      
      expect(deploy_receipt.contract.states.count).to eq(1)
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract: @mint_receipt.contract.address,
          function_name: "id"
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract: @mint_receipt.contract.address,
          function_name: "_mint",
          function_args: {
            "amount": "5",
            to: "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E"
          },
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "calls transfer" do
      @transfer_receipt = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": @creation_receipt.address,
          "functionName": "transfer",
          "args": {
            "amount": "2",
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          },
        }
      )
    end
    
    it "airdrops" do
      @transfer_receipt = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": @creation_receipt.address,
          "functionName": "airdrop",
          "args": {
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
            "amount": "2"
          },
        }
      )
    end
    
    it "bridges" do
      trusted_address = "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
      
      deploy = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "EtherBridge",
          constructorArgs: {
            name: "Bridge Native 1",
            symbol: "PT1",
            trustedSmartContract: trusted_address
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: trusted_address,
        data: {
          "contract": deploy.address,
          functionName: "bridgeIn",
          args: [
            "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            500
          ]
        }
      )
      
      bridge_out = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": deploy.address,
          functionName: "bridgeOut",
          args: {
            amount: 100,
          }
        }
      )
      
      withdrawal_id = bridge_out.logs.detect{|i| i['event'] == 'InitiateWithdrawal'}['data']['withdrawalId']
      
      pending = ContractTransaction.make_static_call(
        contract: deploy.address,
        function_name: "getPendingWithdrawalsForUser",
        function_args: [
          "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
        ]
      )
      
      expect(pending).to eq([withdrawal_id])

      balance = ContractTransaction.make_static_call(
        contract: deploy.address,
        function_name: "balanceOf",
        function_args: [
          "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
        ]
      )
      
      expect(balance).to eq(400)
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: trusted_address,
        data: {
          "contract": deploy.address,
          functionName: "markWithdrawalComplete",
          args: {
            to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            amounts: [100],
            withdrawalIds: [withdrawal_id]
          }
        }
      )
    end
    
    it "bridges_tokens" do
      trusted_address = "0xf99812028817da95f5cf95fb29a2a7eabfbcc27e"
      dc_token_recipient = "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
      
      deploy = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "EthscriptionBridge",
          constructorArgs: {
            name: "Bridge Native 1",
            symbol: "PT1",
            trustedSmartContract: trusted_address,
            # eths on goerli
            ethscriptionDeployId: '0x930c0fa451d2bf96a6f98c2a00080c1551788d20e5664aa2830618e846abb123'
          }
        }
      )

      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: trusted_address,
        data: {
          "contract": deploy.address,
          functionName: "bridgeIn",
          args: {
            to: dc_token_recipient,
            escrowedId: "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6",
          }
        }
      )
      
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: trusted_address,
        data: {
          "contract": deploy.address,
          functionName: "bridgeIn",
          args: {
            to: dc_token_recipient,
            escrowedId: "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6",
          }
        }
      )
      
      balance = ContractTransaction.make_static_call(
        contract: deploy.address,
        function_name: "balanceOf",
        function_args: [
          dc_token_recipient
        ]
      )
      
      expect(balance).to eq(1000 * (10 ** 18))
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: dc_token_recipient,
        data: {
          "contract": deploy.address,
          functionName: "bridgeOut",
          args: {
            escrowedId: "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6",
          }
        }
      )

      balance = ContractTransaction.make_static_call(
        contract: deploy.address,
        function_name: "balanceOf",
        function_args: [
          "0x3A3323d81e77f6a604314aE6278a7B6f4c580928"
        ]
      )
      # binding.pry
      expect(balance).to eq(0)
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: trusted_address,
        data: {
          "contract": deploy.address,
          functionName: "markWithdrawalComplete",
          args: {
            to: dc_token_recipient,
            escrowedId: "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6",
          }
        }
      )
      
      balance = ContractTransaction.make_static_call(
        contract: deploy.address,
        function_name: "pendingWithdrawalEthscriptionToOwner",
        function_args: [
          "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6"
        ]
      )
      # binding.pry
      expect(balance).to eq("0x" + "0" * 40)
    end
    
    it "nfts" do
      data = {
        "protocol": "OpenEditionERC721",
        constructorArgs: {"contentURI"=>
        "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAASABIAAD/4TRcRXhpZgAATU0AKgAAA",
       "name"=>"Purple Cat v2",
       "symbol"=>"PC",
       "maxPerAddress"=>"7 PC",
       "description"=>"cat",
       "mintStart"=>"0",
       "mintEnd"=>"1725030683"}}
      
      trigger_contract_interaction_and_expect_deploy_error(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: data
      )
      
      
      creation = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenEditionERC721",
          "constructorArgs": {
            "name": "Glass Punk Thing-y",
            "symbol": "GP",
            "maxPerAddress": "1000",
            description: "HI!",
            contentURI: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAACXBIWXMAAAsTAAALEwEAmpwYAAAB+0lEQVRIie2VwU4UQRCGv6qanp7ZXUzYgwgJJOpDGIknjibeTXwANb6NkYAejEefwBcw+hZylwsos7PMdvesh2UJibC7LMGT/7nyf/1XdVfL1zFjblF6m+b/AQspm1ewv7tNd6VHf7XPvbW7hFHgx8EBJycnvHrzfS5gZoJPH3dY29hgc2uLhw/us7m+Tqcs6fdXKbsl+7vbywP23j6i6HRRFVJKiAgAIQQAvMtZubPC3rvHMwFXtsi8I6VIPRzgMiPGyPGv3wybU1SNoigIIeK9Xw4AEOKIXCYGVTUgpUSMCYAY4yTJsgDvPVmWk5nhvSe1kcGgpqoqqrqijS29Xg/v3HKAoihwWU5R+vNTphSpq4omNBS5pyzL85lcpUuH/OH9E7pll9w5ityTmQEgolhmOHOUZQczQ8+Gf60E3nvMFFFBVBm3ICgqUHa6qJ2S5w4VYLb/5Qm888SYUDXkzGE8brEsQ1VwLkdEQRSz2W/1UsDzF18wM7iwyUV00iJRVM+gC2z6K/GZGWoZcuEIpoo5h5iiajjnaFO7HAAm8QSlbSftQgTvPW07eQvjdrb51GMhTU3/Mphzi260rmOIHB8dzayZu66nqgc1akabEiFGRqOGn4eHvHz97eaApmkIMUKMhBCohwOGp6O55gsDpnr67PN1yoF/8GX+ATUPoS/WAlmGAAAAAElFTkSuQmCC",
            mintStart: 10.minutes.ago.to_i,
            mintEnd: 1.year.from_now.to_i
          },
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": creation.address,
          "functionName": "mint",
          "args": {
            "amount": "2"
          },
        }
      )
      
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": creation.address,
          "functionName": "mint",
          "args": {
            "amount": "2000"
          },
        }
      )
      
      # expect(mint.status).to eq("call_error")
      
      call_res = ContractTransaction.make_static_call(
        contract: creation.address, 
        function_name: "ownerOf", 
        function_args: { id: "0" }
      )
      
      expect(call_res).to eq('0xC2172a6315c1D7f6855768F843c420EbB36eDa97'.downcase)
      
      expect {
        ContractTransaction.make_static_call(
          contract: creation.address, 
          function_name: "ownerOf", 
          function_args: { id: 100 }
        )
      }.to raise_error(ContractErrors::StaticCallError)
      
      result = ContractTransaction.make_static_call(
        contract: creation.address, 
        function_name: "tokenURI", 
        function_args: { id: "0" }
      )
      expect(result).to match(/\A[\x00-\x7F]*\z/)
    end
    
    it "generative_nfts" do
      script = %{
        var canvas = document.getElementById('canvas');
        var ctx = canvas.getContext('2d');
        var patterns = [];
        var animationId
    
        function Pattern(x, y, size, speed, color) {
          this.x = x;
          this.y = y;
          this.size = size;
          this.speed = speed;
          this.color = color;
        }
        Pattern.prototype.update = function() {
          this.y += this.speed;
          if (this.y > canvas.height) this.y = 0;
        };
        Pattern.prototype.draw = function(ctx) {
          ctx.beginPath();
          ctx.arc(this.x, this.y, this.size, 0, 2 * Math.PI, false);
          ctx.fillStyle = this.color;
          ctx.fill();
        };
    
        function LCG(seed) {
          return function() {
            seed = Math.imul(48271, seed) | 0 % 2147483647;
            return (seed & 2147483647) / 2147483648;
          }
        }
    
        function generateColor(prng) {
          const r = Math.floor(prng() * 256);
          const g = Math.floor(prng() * 256);
          const b = Math.floor(prng() * 256);
          return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
        }
    
        function generateColors(seed, numColors) {
          const prng = LCG(seed);
          const colors = [];
          for (let i = 0; i < numColors; i++) {
            colors.push(generateColor(prng));
          }
          return colors;
        }
        const colors = generateColors(SEED, 5);
        seedPatterns(SEED, colors);
    
        function seedPatterns(seed, colors) {
          patterns = []; // clear existing patterns
          for (var i = 0; i < canvas.width / 8; i++) {
            var colorIndex = Math.floor(((Math.sin(i) * seed) + seed) % colors.length);
            var size = Math.abs(Math.sin(i + seed) * 50);
            var speed = Math.abs(Math.sin(i * seed) * 5);
            var pattern = new Pattern(i * 8, 300, size, speed, colors[colorIndex]);
            patterns.push(pattern);
          }
        }
    
        function animate() {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          ctx.fillStyle = '#1f2227'
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          patterns.forEach(function(p) {
            p.update();
            p.draw(ctx);
          });
          animationId = window.requestAnimationFrame(animate);
        }
    
        function resizeCanvas() {
          canvas.width = window.innerWidth;
          canvas.height = window.innerHeight;
          seedPatterns(SEED, colors); // reinitialize patterns array after every resize
          window.cancelAnimationFrame(animationId)
          animate();
        }
    
        function debounce(func, timeout = 300) {
          let timer;
          return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => {
              func.apply(this, args);
            }, timeout);
          };
        }
        resizeCanvas();
        window.addEventListener('resize', debounce(resizeCanvas, 50));
      }
    
      creation = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "GenerativeERC721",
          "constructorArgs": {
            "name": "Art-y Thing-y",
            "symbol": "AT",
            "maxPerAddress": "1000",
            maxSupply: 1000,
            description: "HI!",
            generativeScript: script
          },
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": creation.address,
          "functionName": "mint",
          "args": {
            "amount": "2"
          },
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": creation.address,
          "functionName": "transferFrom",
          "args": {
            "from": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            id: 1
          },
        }
      )
      
      result = ContractTransaction.make_static_call(
        contract: creation.address, 
        function_name: "tokenURI", 
        function_args: { id: "1" }
      )
      
      expect(result).to match(/\A[\x00-\x7F]*\z/)
    end
    
    it "dexes" do
      token0 = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "PublicMintERC20",
          "constructorArgs": {
            "name": "Pool Token 1",
            "symbol": "PT1",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      token1 = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "PublicMintERC20",
          "constructorArgs": {
            "name": "Pool Token 2",
            "symbol": "PT2",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      dex = trigger_contract_interaction_and_expect_success(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "ERC20LiquidityPool",
          constructorArgs: {
            token0: token0.address,
            token1: token1.address
          }
        }
      ).contract
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": token0.address,
          functionName: "mint",
          args: {
            amount: 500
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": token1.address,
          functionName: "mint",
          args: {
            amount: "600"
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": token1.address,
          functionName: "approve",
          args: {
            spender: dex.address,
            amount: (21e6).to_i
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": token0.address,
          functionName: "approve",
          args: {
            spender: dex.address,
            amount: (21e6).to_i
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
        data: {
          "contract": dex.address,
          functionName: "addLiquidity",
          args: {
            token0Amount: 200,
            token1Amount: 100
          }
        }
      )
      
      x = ContractTransaction.make_static_call(
        contract: dex.address,
        function_name: "reserves"
      )
      
      expect(x).to be_a(Hash)
      
      a = ContractTransaction.make_static_call(
        contract: token0.address,
        function_name: "balanceOf",
        function_args: [
          "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        ]
      )
      expect(a).to eq(300)
      
      trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contract": dex.address,
          functionName: "swap",
          args: {
            inputAmount: 50,
            outputToken: token1.address,
            inputToken: token0.address,
          }
        }
      )
      
      finalTokenABalance = ContractTransaction.make_static_call(
        contract: token0.address,
        function_name: "balanceOf",
        function_args: {
          arg0: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
      
      expect(finalTokenABalance).to eq(250)
      
      finalTokenBBalance = ContractTransaction.make_static_call(
        contract: token1.address,
        function_name: "balanceOf",
        function_args: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
      )
      
      expect(finalTokenBBalance).to be > 500
      
      calculate_output_amount = ContractTransaction.make_static_call(
        contract: dex.address,
        function_name: "calculateOutputAmount",
        function_args: {
          inputToken: token0.address,
          outputToken: token1.address,
          inputAmount: 50
        }
      )
    end
  end
end
