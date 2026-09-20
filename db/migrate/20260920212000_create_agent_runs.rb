class CreateAgentRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_runs, id: :string do |t|
      t.references :room, null: false, foreign_key: true
      t.string :owner_profile_id, null: false
      t.string :runtime_id, null: false
      t.string :external_run_id, null: false
      t.string :title, null: false
      t.string :state, null: false
      t.integer :owner_generation, null: false
      t.integer :source_revision, null: false
      t.integer :version, null: false, default: 1
      t.string :parent_run_id
      t.string :retry_of_run_id
      t.string :continuation_of_run_id
      t.string :invocation_id
      t.integer :initiating_message_id
      t.string :session_ref
      t.string :reconciliation_reference
      t.json :context, null: false
      t.text :summary
      t.datetime :last_reported_at, null: false
      t.boolean :needs_reconciliation, null: false, default: false
      t.timestamps
    end
    add_foreign_key :agent_runs, :agent_profiles, column: :owner_profile_id
    add_index :agent_runs, [ :runtime_id, :external_run_id ], unique: true
    add_index :agent_runs, :invocation_id, unique: true
    add_index :agent_runs, [ :room_id, :created_at ]
    create_table :agent_participants, id: :string do |t|
      t.string :run_id, null: false
      t.string :profile_id, null: false
      t.json :contributions, null: false
      t.timestamps
    end
    add_index :agent_participants, [ :run_id, :profile_id ], unique: true
    create_table :agent_run_messages, id: :string do |t|
      t.string :run_id, null: false
      t.string :author_kind, null: false
      t.string :author_id, null: false
      t.text :body_text, null: false
      t.integer :revision, null: false, default: 1
      t.string :client_message_id, null: false
      t.timestamps
    end
    add_index :agent_run_messages, [ :run_id, :author_id, :client_message_id ], unique: true
    create_table :agent_activities, id: :string do |t|
      t.string :run_id, null: false
      t.string :profile_id, null: false
      t.string :operation_id, null: false
      t.json :operation, null: false
      t.timestamps
    end
    add_index :agent_activities, [ :run_id, :profile_id, :operation_id ], unique: true
    create_table :agent_artifacts, id: :string do |t|
      t.references :room, null: false, foreign_key: true
      t.string :run_id
      t.string :publisher_profile_id, null: false
      t.string :title, null: false
      t.string :kind, null: false
      t.string :sha256
      t.string :external_uri
      t.string :external_ref
      t.timestamps
    end
    %i[ participants run_messages activities artifacts ].each do |name|
      add_foreign_key "agent_#{name}", :agent_runs, column: :run_id
    end
    add_foreign_key :agent_participants, :agent_profiles, column: :profile_id
    add_foreign_key :agent_activities, :agent_profiles, column: :profile_id
    add_foreign_key :agent_artifacts, :agent_profiles, column: :publisher_profile_id
  end
end
