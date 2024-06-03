class ContractFunctionArgs
  def initialize(args = {})
    @args = args
  end
  
  def get_arg(arg_name)
    TransactionContext.log_call("ContractFunctionArgs", "ContractFunctionArgs", "Get Arg") do
      TransactionContext.increment_gas("ContractFunctionArgGet")
      @args[arg_name]
    end
  end
end
