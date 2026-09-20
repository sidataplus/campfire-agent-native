class CreateAgentDecisions < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_actions, id: :string do |t|
      t.string :profile_id, null: false
      t.references :room, null: false, foreign_key: true
      t.string :run_id
      t.string :invocation_id
      t.string :kind, null: false
      t.string :operation, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.json :arguments, null: false
      t.json :input_schema, null: false
      t.json :subject_references, null: false
      t.json :reviewer_user_ids, null: false
      t.string :proposal_digest, null: false
      t.string :stream_epoch, null: false
      t.integer :run_version
      t.integer :owner_generation
      t.string :state, null: false, default: "pending"
      t.integer :version, null: false, default: 1
      t.string :decision_receipt_id
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_foreign_key :agent_actions, :agent_profiles, column: :profile_id
    add_foreign_key :agent_actions, :agent_runs, column: :run_id
    add_foreign_key :agent_actions, :agent_invocations, column: :invocation_id
    add_index :agent_actions, [ :profile_id, :state, :expires_at ]
    create_table :agent_receipts, id: :string do |t|
      t.string :profile_id, null: false
      t.references :room, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :subject_type, null: false
      t.string :subject_id, null: false
      t.string :actor_kind, null: false
      t.string :actor_id, null: false
      t.string :result, null: false
      t.json :evidence, null: false
      t.json :payload, null: false
      t.string :runtime_operation_id
      t.integer :source_revision
      t.string :decision_receipt_id
      t.datetime :created_at, null: false
    end
    add_foreign_key :agent_receipts, :agent_profiles, column: :profile_id
    add_index :agent_receipts, [ :profile_id, :runtime_operation_id, :source_revision ], unique: true, name: "agent_receipt_runtime_revision"
    add_index :agent_receipts, [ :subject_type, :subject_id ], unique: true, where: "kind = 'human_intent'", name: "agent_single_human_intent"
    create_table :agent_attention_reads, id: :string do |t|
      t.references :user, null: false, foreign_key: true
      t.string :item_id, null: false
      t.boolean :read, null: false, default: false
      t.timestamps
    end
    add_index :agent_attention_reads, [ :user_id, :item_id ], unique: true
  end
end
