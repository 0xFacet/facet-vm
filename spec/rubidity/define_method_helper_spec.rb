require 'rails_helper'

RSpec.describe DefineMethodHelper do
  
  def eval_and_expect_error(code)
    expect { eval(code) }.to raise_error(DefineMethodHelper::MethodAlreadyDefinedError)
  end
    
  context 'when defining methods' do
    it 'raises an error if the method is already defined' do
      code = <<~RUBY
        Class.new do
          include DefineMethodHelper
          
          def test_method
          end
          
          define_method_with_check(:test_method) do
          end
        end
      RUBY
      
      eval_and_expect_error(code)
      
      # code = <<~RUBY
      #   class TestClass2
      #     include DefineMethodHelper
          
      #     define_method_with_check(:test_method) do
      #     end
          
      #     def test_method
      #     end
      #   end
      # RUBY
      
      # eval_and_expect_error(code)
      
      code = <<~RUBY
        Class.new do
          include DefineMethodHelper
          
          def initialize
            define_singleton_method_with_check(:test_method) do
            end
          end
          
          def test_method
          end
        end.new
      RUBY
      
      eval_and_expect_error(code)
      
      # code = <<~RUBY
      #   class TestClass4
      #     include DefineMethodHelper
          
      #     define_singleton_method_with_check(:test_method) do
      #     end
          
      #     def self.test_method
      #     end
      #   end
      # RUBY
      
      # eval_and_expect_error(code)
      
      code = <<~RUBY
        Class.new do
          include DefineMethodHelper
          
          def self.test_method2
          end
          
          def initialize
            define_singleton_method_with_check(:test_method) do
            end
          end
        end.new
      RUBY
      
      expect { eval(code) }.not_to raise_error
    end
  end
end
