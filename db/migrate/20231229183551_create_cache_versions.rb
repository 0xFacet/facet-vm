class CreateCacheVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :cache_versions do |t|
      t.integer :version, null: false, default: 1

      t.timestamps
    end
    
    CacheVersion.create! unless CacheVersion.exists?
  end
end
