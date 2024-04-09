module TokenDataProcessor
  extend ActiveSupport::Concern

  class_methods do
    def process_swaps(contract_address:, paired_token_address:, router_addresses:, from_address:, from_timestamp:, to_timestamp:)
      transactions = TransactionReceipt.where(
        to_contract_address: router_addresses,
        status: "success",
        function: ["swapExactTokensForTokens", "swapTokensForExactTokens"]
      )
        .where("block_timestamp >= ? AND block_timestamp <= ?", from_timestamp, to_timestamp)
        .where("EXISTS (
          SELECT 1
          FROM jsonb_array_elements(logs) AS log
          WHERE (log ->> 'contractAddress') = ?
          AND (log ->> 'event') = 'Transfer'
        )", contract_address)

      transactions = transactions.where(to_contract_address: router_addresses) if router_addresses.present?
      transactions = transactions.where(from_address: from_address) if from_address.present?

      if transactions.blank?
        render json: { error: "Transactions not found" }, status: 404
        return
      end

      cooked_transactions = transactions.map do |receipt|
        relevant_transfer_logs = receipt.logs.select do |log|
          log["event"] == "Transfer" && !router_addresses.include?(log["data"]["to"])
        end

        token_log = relevant_transfer_logs.detect do |log|
          log['contractAddress'] == contract_address
        end

        paired_token_log = (relevant_transfer_logs - [token_log]).first

        next if paired_token_address.present? && paired_token_log['contractAddress'] != paired_token_address

        swap_type = if token_log['data']['to'] == receipt.from_address
          'buy'
        else
          'sell'
        end

        {
          txn_hash: receipt.transaction_hash,
          swapper_address: receipt.from_address,
          timestamp: receipt.block_timestamp,
          token_amount: token_log['data']['amount'],
          paired_token_amount: paired_token_log['data']['amount'],
          paired_token_address: paired_token_log['contractAddress'],
          swap_type: swap_type,
          transaction_index: receipt.transaction_index,
          block_number: receipt.block_number
        }
      end

      cooked_transactions.compact
    end
  end
end
