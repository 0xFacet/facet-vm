require 'rails_helper'

RSpec.describe Contract, type: :model do
  before do
    ENV['INDEXER_API_BASE_URI'] = "http://localhost:4000/api"
    
    @creation_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "OpenMintToken",
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

  describe ".deploy_new_contract_from_ethscription_if_needed!" do
    it "creates a new contract" do
      expect(@creation_receipt.status).to eq("success")
    end
  end

  describe ".call_contract_from_ethscription_if_needed!" do
    before do
      @mint_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "mint",
          "args": {
            "amount": "5"
          },
        }
      )
    end
    
    it "won't call constructor after deployed" do
      r = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
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
      
      expect(r.status).to eq("call_error")
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract_id: @mint_receipt.contract.contract_id,
          function_name: "id"
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract_id: @mint_receipt.contract.contract_id,
          function_name: "_mint",
          function_args: {
            "amount": "5",
            to: "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E"
          },
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "mints the contract" do
      expect(@mint_receipt.status).to eq("success")
    end
    
    it "calls transfer" do
      @transfer_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "transfer",
          "args": {
            "amount": "2",
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          },
        }
      )
      expect(@transfer_receipt.status).to eq("success")
    end
    
    it "airdrops" do
      @transfer_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "airdrop",
          "args": {
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
            "amount": "2"
          },
        }
      )
      # pp @transfer_receipt.contract.load_current_state
      expect(@transfer_receipt.status).to eq("success")
    end
    
    it "bridges" do
      trusted_address = "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
      
      deploy = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "BridgeableToken",
          constructorArgs: {
            name: "Bridge Native 1",
            symbol: "PT1",
            trustedSmartContract: trusted_address
          }
        }
      )
      
      expect(deploy.status).to eq("success")
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: trusted_address,
        data: {
          "contractId": deploy.contract_id,
          functionName: "bridgeIn",
          args: {
            to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            amount: 500,
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": deploy.contract_id,
          functionName: "bridgeOut",
          args: {
            amount: 100,
          }
        }
      )
      # binding.pry

      balance = ContractTransaction.make_static_call(
        contract_id: deploy.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
        }
      )
      # binding.pry
      expect(balance).to eq(400)
      
      out = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: trusted_address,
        data: {
          "contractId": deploy.contract_id,
          functionName: "markWithdrawalComplete",
          args: {
            to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            amount: 100,
          }
        }
      )
      
      expect(out.status).to eq("success")
    end
    
    it "bridges_tokens" do
      trusted_address = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      
      deploy = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "EthsTokenBridge",
          constructorArgs: {
            name: "Bridge Native 1",
            symbol: "PT1",
            trustedSmartContract: trusted_address
          }
        }
      )
      
      expect(deploy.status).to eq("success")
      
      mint = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: trusted_address,
        data: {
          "contractId": deploy.contract_id,
          functionName: "bridgeIn",
          args: {
            to: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928",
            escrowedId: "0xd63053076a037e25dd76b53b603ef6d6b3c490d030e80929f7f6e2c62d09e6f6",
          }
        }
      )
      
      expect(mint.status).to eq("success")
      
      balance = ContractTransaction.make_static_call(
        contract_id: deploy.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928"
        }
      )
      
      expect(balance).to eq(1000)
      
      out = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928",
        data: {
          "contractId": deploy.contract_id,
          functionName: "bridgeOut",
          args: {
            amount: 1000,
          }
        }
      )
      
      expect(out.status).to eq("success")

      balance = ContractTransaction.make_static_call(
        contract_id: deploy.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928"
        }
      )
      # binding.pry
      expect(balance).to eq(0)
      
      complete = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: trusted_address,
        data: {
          "contractId": deploy.contract_id,
          functionName: "markWithdrawalComplete",
          args: {
            to: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928",
            amount: 1000,
          }
        }
      )
      
      expect(complete.status).to eq("success")
      
      balance = ContractTransaction.make_static_call(
        contract_id: deploy.contract_id,
        function_name: "pendingWithdrawals",
        function_args: {
          arg0: "0x3A3323d81e77f6a604314aE6278a7B6f4c580928"
        }
      )
      # binding.pry
      expect(balance).to eq(0)
    end
    
    it "nfts" do
      creation = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenEditionNft",
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
      
      expect(creation.status).to eq("success")
      
      mint = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": creation.contract_id,
          "functionName": "mint",
          "args": {
            "amount": "2"
          },
        }
      )
      
      expect(mint.status).to eq("success")
      
      mint = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": creation.contract_id,
          "functionName": "mint",
          "args": {
            "amount": "2000"
          },
        }
      )
      
      expect(mint.status).to eq("call_error")
      
      call_res = ContractTransaction.make_static_call(
        contract_id: creation.contract_id, 
        function_name: "ownerOf", 
        function_args: { id: "0" }
      )
      
      expect(call_res).to eq('0xC2172a6315c1D7f6855768F843c420EbB36eDa97'.downcase)
      
      expect {
        ContractTransaction.make_static_call(
          contract_id: creation.contract_id, 
          function_name: "ownerOf", 
          function_args: { id: 100 }
        )
      }.to raise_error(ContractErrors::StaticCallError)
      
      result = ContractTransaction.make_static_call(
        contract_id: creation.contract_id, 
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
    
      creation = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "GenerativeNft",
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
      
      expect(creation.status).to eq("success")
      
      mint = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": creation.contract_id,
          "functionName": "mint",
          "args": {
            "amount": "2"
          },
        }
      )
      
      expect(mint.status).to eq("success")
      
      result = ContractTransaction.make_static_call(
        contract_id: creation.contract_id, 
        function_name: "tokenURI", 
        function_args: { id: "1" }
      )
      
      expect(result).to match(/\A[\x00-\x7F]*\z/)
    end
    
    it "dexes" do
      token_0 = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenMintToken",
          "constructorArgs": {
            "name": "Pool Token 1",
            "symbol": "PT1",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      token_1 = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenMintToken",
          "constructorArgs": {
            "name": "Pool Token 2",
            "symbol": "PT2",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      dex = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "DexLiquidityPool",
          constructorArgs: {
            token0: token_0.contract_id,
            token1: token_1.contract_id
          }
        }
      ).contract
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_0.contract_id,
          functionName: "mint",
          args: {
            amount: 500
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_1.contract_id,
          functionName: "mint",
          args: {
            amount: 600
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_1.contract_id,
          functionName: "approve",
          args: {
            spender: dex.contract_id,
            amount: (21e6).to_i
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_0.contract_id,
          functionName: "approve",
          args: {
            spender: dex.contract_id,
            amount: (21e6).to_i
          }
        }
      )
      
      add_liq = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
        data: {
          "contractId": dex.contract_id,
          functionName: "add_liquidity",
          args: {
            token_0_amount: 200,
            token_1_amount: 100
          }
        }
      )
      
      expect(add_liq.status).to eq("success")
      
      a = ContractTransaction.make_static_call(
        contract_id: token_0.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
# binding.pry
      expect(a).to eq(300)
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": dex.contract_id,
          functionName: "swap",
          args: {
            input_amount: 50,
            output_token: token_1.contract_id,
            input_token: token_0.contract_id,
          }
        }
      )
      
      final_token_a_balance = ContractTransaction.make_static_call(
        contract_id: token_0.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
      
      expect(final_token_a_balance).to eq(250)
      
      final_token_b_balance = ContractTransaction.make_static_call(
        contract_id: token_1.contract_id,
        function_name: "balanceOf",
        function_args: {
          arg0: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
      
      expect(final_token_b_balance).to be > 500
      
      calculate_output_amount = ContractTransaction.make_static_call(
        contract_id: dex.contract_id,
        function_name: "calculate_output_amount",
        function_args: {
          input_token: token_0.contract_id,
          output_token: token_1.contract_id,
          input_amount: 50
        }
      )
    end
  end
end
