class RemoveUniqueIndexFromEthscriptionsContentSha < ActiveRecord::Migration[7.0]
  def change
    # Remove the unique index
    remove_index :ethscriptions, :content_sha
    # Add the index back, but without the uniqueness constraint
    add_index :ethscriptions, :content_sha
  end
end
