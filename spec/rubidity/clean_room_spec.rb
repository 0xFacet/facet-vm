require 'rails_helper'

RSpec.describe CleanRoom do
  let(:context) { double("Context") }
  let(:allowed_methods) { [:allowed_method] }
  let(:valid_call_proc) { Proc.new { |method| allowed_methods.include?(method) } }
  let(:filename_and_line) { ["test_filename", 1] }
  
  describe ".execute_user_code_on_context" do
    context "when given a block" do
      it "executes the block only if the method is allowed" do
        allow(context).to receive(:allowed_method).and_return("Method Executed")
        block = -> { allowed_method }

        result = CleanRoom.execute_user_code_on_context(context, valid_call_proc, "allowed_method", block)
        expect(result).to eq("Method Executed")
      end

      it "does not execute the block if the method is not allowed" do
        expect {
          CleanRoom.execute_user_code_on_context(context, valid_call_proc, "not_allowed_method", -> { not_allowed_method })
        }.to raise_error(NameError)
      end
    end

    context "when given a string of code" do
      it "executes the string only if the method is allowed" do
        allow(context).to receive(:allowed_method).and_return("Method Executed")
        code = "allowed_method"

        result = CleanRoom.execute_user_code_on_context(context, valid_call_proc, "allowed_method", code, *filename_and_line)
        expect(result).to eq("Method Executed")
      end

      it "does not execute the string if the method is not allowed" do
        expect {
          CleanRoom.execute_user_code_on_context(context, valid_call_proc, "not_allowed_method", code, *filename_and_line)
        }.to raise_error(NameError)
      end
    end
  end
end
