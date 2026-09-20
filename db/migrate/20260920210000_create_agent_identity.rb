class CreateAgentIdentity < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :native_agent, :boolean, default: false, null: false
    add_column :messages, :agent_revision, :integer, default: 1, null: false
    create_table :agent_instances do |t|
      t.string :instance_uuid, null: false
      t.string :stream_epoch, null: false
      t.string :recovery_digest, null: false
      t.boolean :recovery_required, default: true, null: false
      t.integer :event_floor, default: 0, null: false
      t.timestamps
    end
    create_table :agent_profiles, id: :string do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :runtime_id, null: false
      t.json :manifest, null: false, default: {}
      t.boolean :enabled, default: true, null: false
      t.integer :authorization_version, default: 1, null: false
      t.timestamps
    end
    create_table :agent_credentials, id: :string do |t|
      t.string :profile_id, null: false
      t.string :token_digest, null: false
      t.json :scopes, default: [], null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :agent_credentials, :token_digest, unique: true
    create_table :agent_room_grants, id: :string do |t|
      t.string :profile_id, null: false
      t.references :room, null: false, foreign_key: true
      t.string :history_policy, null: false, default: "since_grant"
      t.string :activation, null: false, default: "explicit"
      t.timestamps
    end
    add_index :agent_room_grants, [:profile_id, :room_id], unique: true
    create_table :agent_operator_grants, id: :string do |t|
      t.string :profile_id, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :agent_operator_grants, [:profile_id, :user_id], unique: true
    create_table :agent_write_receipts, id: :string do |t|
      t.string :principal, null: false
      t.string :key_digest, null: false
      t.string :request_digest, null: false
      t.json :result, null: false
      t.timestamps
    end
    add_index :agent_write_receipts, [:principal, :key_digest], unique: true
    create_table :agent_uploads, id: :string do |t|
      t.string :profile_id, null: false
      t.references :room, null: false, foreign_key: true
      t.string :sha256, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    %i[credentials room_grants operator_grants uploads].each do |name|
      add_foreign_key "agent_#{name}", :agent_profiles, column: :profile_id
    end
  end
end
