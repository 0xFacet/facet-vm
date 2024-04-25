require 'rails_helper'

RSpec.describe UltraMinimalProxy do
  let(:context) { double("Context") }
  let(:allowed_methods) { [:allowed_method] }
  let(:valid_call_proc) { Proc.new { |method| allowed_methods.include?(method) } }
  let(:filename_and_line) { ["test_filename", 1] }
  
  describe ".execute_user_code_on_context" do
    it "does things" do
      code = <<~RUBY
      pragma :rubidity, "1.0.0"
      contract :A do
        string :deserialize
        uint256 :secret
        
        constructor do
          # ::Kernel.binding.pry
          s.deserialize({secret: 10})
          # s.load({secret: 9})
        end
      end
      RUBY
      
      artifact = RubidityTranspiler.new(code).get_desired_artifact("A")
      
      imp = artifact.build_class.new
      
      expect { imp.constructor }.to raise_error(NoMethodError)
      
      expect(imp.state_manager.serialize).to eq(
        {"deserialize"=>"", "secret"=>0}
      )
    end
  end
end
