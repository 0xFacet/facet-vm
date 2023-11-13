require 'rails_helper'

RSpec.describe ContractAstPreprocessor do
  let(:unused_reference) { File.expand_path('../../fixtures/TestUnusedReference.rubidity', __FILE__) }
  let(:dupe_contract) { File.expand_path('../../fixtures/TestDuplicateContract.rubidity', __FILE__) }
  
  def test_preprocessor(code, expected_output)
    contract_ast = Unparser.parse(code)
    ast = ContractAstPreprocessor.process(contract_ast)
    code = ast.unparse
    
    expect(code).to eq(expected_output)
  end
  
  it "disallows duplicate contract names" do
    expect {
      RubidityTranspiler.transpile_file(dupe_contract)
    }.to raise_error(/Duplicate contract names.*/)
  end
  
  it "rewrites constants" do
    code = <<~RUBY
      contract :A do
      end
      contract :D do
      end
      contract :B, is: :D do
        function :test do
          B.constructor
          A._mint
          C.blah
          D.fun
        end
      end
    RUBY
    
    output = <<~RUBY
      contract(:A) {
      }
      contract(:D) {
      }
      contract(:B, is: :D) {
        function(:test) {
          self.B.constructor
          self.A._mint
          C.blah
          self.D.fun
        }
      }
    RUBY
    
    test_preprocessor(code, output)
  end
  
  it "works on files" do
    normalized = <<~RUBY
      pragma(:rubidity, "1.0.0")
      contract(:Dep1) {
      }
      contract(:Dep2) {
      }
      contract(:TestUnusedReference, is: [:Dep1, :Dep2]) {
      }
    RUBY
    
    transpiled = RubidityTranspiler.transpile_file(unused_reference)
    
    expect(transpiled.last[:source_code]).to eq(normalized)
  end

  it "retains the bottom contract" do
    code = <<~RUBY
      contract :Bottom do
      end
    RUBY
    
    normalized = <<~RUBY
      (contract(:Bottom) {
      })
    RUBY
    
    test_preprocessor(code, normalized)
  end
  
  it "removes contracts with no dependencies except the bottom one" do
    code = <<~RUBY
      contract :A do
      end
      
      contract :B do
      end
      
      contract :Bottom do
      end
    RUBY
  
    normalized = <<~RUBY
      (contract(:Bottom) {
      })
    RUBY
    
    test_preprocessor(code, normalized)
  end
  
  it "removes contracts with dependencies on removed contracts" do
    code = <<~RUBY
      contract :A do
      end
      
      contract :B, is: :A do
      end
      
      contract :Bottom do
      end
    RUBY
  
    normalized = <<~RUBY
      (contract(:Bottom) {
      })
    RUBY
    
    test_preprocessor(code, normalized)
  end
  
  it "resolves sorting ambiguity through lexical sorting" do
    code = <<~RUBY
      contract :A do
      end
    
      contract :C, is: :A do
      end
      
      contract :B, is: :A do
      end
      
      contract :Bottom, is: [:B, :C] do
      end
    RUBY
  
    normalized = <<~RUBY
      contract(:A) {
      }
      contract(:B, is: :A) {
      }
      contract(:C, is: :A) {
      }
      contract(:Bottom, is: [:B, :C]) {
      }
    RUBY
    
    test_preprocessor(code, normalized)
  end
  
  it "tests several things" do
    code = <<~RUBY
    contract :A do
    end
    
    contract :X do
    end
    
    contract :Random, is: :A do
    end
    
    contract :AFKJ, is: :A do
    end
          
    contract :AFKZ, is: :A do
    end
    
    contract :BottomContract, is: [:AFKJ, :AFKZ] do
    end
    RUBY
    
    normalized = <<~RUBY
    contract(:A) {
    }
    contract(:AFKJ, is: :A) {
    }
    contract(:AFKZ, is: :A) {
    }
    contract(:BottomContract, is: [:AFKJ, :AFKZ]) {
    }
    RUBY
    
    test_preprocessor(code, normalized)
  end
end
