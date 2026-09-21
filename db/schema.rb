# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_09_20_220000) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "custom_styles"
    t.string "join_code", null: false
    t.string "name", null: false
    t.json "settings"
    t.integer "singleton_guard", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["singleton_guard"], name: "index_accounts_on_singleton_guard", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_actions", id: :string, force: :cascade do |t|
    t.json "arguments", null: false
    t.datetime "created_at", null: false
    t.string "decision_receipt_id"
    t.text "description", null: false
    t.datetime "expires_at", null: false
    t.json "input_schema", null: false
    t.string "invocation_id"
    t.string "kind", null: false
    t.string "operation", null: false
    t.integer "owner_generation"
    t.string "profile_id", null: false
    t.string "proposal_digest", null: false
    t.json "reviewer_user_ids", null: false
    t.integer "room_id", null: false
    t.string "run_id"
    t.integer "run_version"
    t.string "state", default: "pending", null: false
    t.string "stream_epoch", null: false
    t.json "subject_references", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["profile_id", "state", "expires_at"], name: "index_agent_actions_on_profile_id_and_state_and_expires_at"
    t.index ["room_id"], name: "index_agent_actions_on_room_id"
  end

  create_table "agent_activities", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "operation", null: false
    t.string "operation_id", null: false
    t.string "profile_id", null: false
    t.string "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "profile_id", "operation_id"], name: "idx_on_run_id_profile_id_operation_id_fec4f0154c", unique: true
  end

  create_table "agent_artifacts", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_ref"
    t.string "external_uri"
    t.string "kind", null: false
    t.string "publisher_profile_id", null: false
    t.integer "room_id", null: false
    t.string "run_id"
    t.string "sha256"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_agent_artifacts_on_room_id"
  end

  create_table "agent_attention_reads", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "item_id", null: false
    t.boolean "read", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "item_id"], name: "index_agent_attention_reads_on_user_id_and_item_id", unique: true
    t.index ["user_id"], name: "index_agent_attention_reads_on_user_id"
  end

  create_table "agent_consumers", id: :string, force: :cascade do |t|
    t.integer "authorization_version", null: false
    t.integer "checkpoint", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "delivered", default: 0, null: false
    t.integer "enrollment_floor", default: 0, null: false
    t.json "event_types", default: [], null: false
    t.string "name", null: false
    t.string "profile_id", null: false
    t.json "room_ids", default: [], null: false
    t.string "stream_epoch", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id", "name"], name: "index_agent_consumers_on_profile_id_and_name", unique: true
  end

  create_table "agent_credentials", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "profile_id", null: false
    t.datetime "revoked_at"
    t.json "scopes", default: [], null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_agent_credentials_on_token_digest", unique: true
  end

  create_table "agent_events", force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_kind", default: "system", null: false
    t.datetime "created_at", null: false
    t.string "event_uuid", null: false
    t.string "kind", null: false
    t.string "profile_id"
    t.string "resource_id", null: false
    t.integer "resource_revision"
    t.string "resource_type", null: false
    t.integer "room_id"
    t.datetime "updated_at", null: false
    t.index ["event_uuid"], name: "index_agent_events_on_event_uuid", unique: true
    t.index ["profile_id", "id"], name: "index_agent_events_on_profile_id_and_id"
    t.index ["room_id", "id"], name: "index_agent_events_on_room_id_and_id"
  end

  create_table "agent_instances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_floor", default: 0, null: false
    t.string "instance_uuid", null: false
    t.string "recovery_digest", null: false
    t.boolean "recovery_required", default: true, null: false
    t.string "stream_epoch", null: false
    t.datetime "updated_at", null: false
  end

  create_table "agent_invocations", id: :string, force: :cascade do |t|
    t.datetime "admission_expires_at", null: false
    t.json "context", null: false
    t.datetime "created_at", null: false
    t.string "disposition", default: "pending", null: false
    t.integer "human_user_id", null: false
    t.text "normalized_input", null: false
    t.string "profile_id", null: false
    t.integer "room_id", null: false
    t.string "run_id"
    t.string "runtime_operation_id"
    t.json "source", null: false
    t.string "source_digest", null: false
    t.string "stream_epoch", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["human_user_id"], name: "index_agent_invocations_on_human_user_id"
    t.index ["profile_id", "runtime_operation_id"], name: "index_agent_invocations_on_profile_id_and_runtime_operation_id", unique: true
    t.index ["room_id"], name: "index_agent_invocations_on_room_id"
  end

  create_table "agent_maintenance_audits", id: :string, force: :cascade do |t|
    t.string "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "evidence_reference", null: false
    t.json "metadata", default: {}, null: false
    t.string "operation", null: false
  end

  create_table "agent_message_tombstones", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "profile_id", null: false
    t.integer "revision", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_agent_message_tombstones_on_room_id"
  end

  create_table "agent_notifications", id: :string, force: :cascade do |t|
    t.string "action_id"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "event_uuid", null: false
    t.string "last_error_class"
    t.datetime "ready_at", null: false
    t.integer "room_id", null: false
    t.string "run_id"
    t.string "state", default: "pending", null: false
    t.integer "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["event_uuid", "subscription_id"], name: "index_agent_notifications_on_event_uuid_and_subscription_id", unique: true
    t.index ["state", "ready_at"], name: "index_agent_notifications_on_state_and_ready_at"
  end

  create_table "agent_operator_grants", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "profile_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["profile_id", "user_id"], name: "index_agent_operator_grants_on_profile_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_agent_operator_grants_on_user_id"
  end

  create_table "agent_participants", id: :string, force: :cascade do |t|
    t.json "contributions", null: false
    t.datetime "created_at", null: false
    t.string "profile_id", null: false
    t.string "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "profile_id"], name: "index_agent_participants_on_run_id_and_profile_id", unique: true
  end

  create_table "agent_profiles", id: :string, force: :cascade do |t|
    t.integer "authorization_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.json "manifest", default: {}, null: false
    t.string "runtime_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_agent_profiles_on_user_id", unique: true
  end

  create_table "agent_receipts", id: :string, force: :cascade do |t|
    t.string "actor_id", null: false
    t.string "actor_kind", null: false
    t.datetime "created_at", null: false
    t.string "decision_receipt_id"
    t.json "evidence", null: false
    t.string "kind", null: false
    t.json "payload", null: false
    t.string "profile_id", null: false
    t.string "result", null: false
    t.integer "room_id", null: false
    t.string "runtime_operation_id"
    t.integer "source_revision"
    t.string "subject_id", null: false
    t.string "subject_type", null: false
    t.index ["profile_id", "runtime_operation_id", "source_revision"], name: "agent_receipt_runtime_revision", unique: true
    t.index ["profile_id", "subject_type", "subject_id"], name: "agent_single_action_admission", unique: true, where: "subject_type = 'action' AND kind = 'admission' AND result = 'accepted'"
    t.index ["room_id"], name: "index_agent_receipts_on_room_id"
    t.index ["subject_type", "subject_id"], name: "agent_single_human_intent", unique: true, where: "kind = 'human_intent'"
  end

  create_table "agent_room_grants", id: :string, force: :cascade do |t|
    t.string "activation", default: "explicit", null: false
    t.datetime "created_at", null: false
    t.string "history_policy", default: "since_grant", null: false
    t.string "profile_id", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id", "room_id"], name: "index_agent_room_grants_on_profile_id_and_room_id", unique: true
    t.index ["room_id"], name: "index_agent_room_grants_on_room_id"
  end

  create_table "agent_run_messages", id: :string, force: :cascade do |t|
    t.string "author_id", null: false
    t.string "author_kind", null: false
    t.text "body_text", null: false
    t.string "client_message_id", null: false
    t.datetime "created_at", null: false
    t.integer "revision", default: 1, null: false
    t.string "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "author_id", "client_message_id"], name: "idx_on_run_id_author_id_client_message_id_08c98141eb", unique: true
  end

  create_table "agent_runs", id: :string, force: :cascade do |t|
    t.json "context", null: false
    t.string "continuation_of_run_id"
    t.datetime "created_at", null: false
    t.string "external_run_id", null: false
    t.integer "initiating_message_id"
    t.string "invocation_id"
    t.datetime "last_reported_at", null: false
    t.boolean "needs_reconciliation", default: false, null: false
    t.integer "owner_generation", null: false
    t.string "owner_profile_id", null: false
    t.string "outcome_receipt_id"
    t.string "parent_run_id"
    t.string "reconciliation_reference"
    t.string "retry_of_run_id"
    t.integer "room_id", null: false
    t.string "runtime_id", null: false
    t.string "session_ref"
    t.integer "source_revision", null: false
    t.string "state", null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["invocation_id"], name: "index_agent_runs_on_invocation_id", unique: true
    t.index ["outcome_receipt_id"], name: "index_agent_runs_on_outcome_receipt_id", unique: true
    t.index ["room_id", "created_at"], name: "index_agent_runs_on_room_id_and_created_at"
    t.index ["room_id"], name: "index_agent_runs_on_room_id"
    t.index ["runtime_id", "external_run_id"], name: "index_agent_runs_on_runtime_id_and_external_run_id", unique: true
  end

  create_table "agent_uploads", id: :string, force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "profile_id", null: false
    t.integer "room_id", null: false
    t.string "sha256", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_agent_uploads_on_room_id"
  end

  create_table "agent_write_receipts", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key_digest", null: false
    t.string "principal", null: false
    t.string "request_digest", null: false
    t.json "result", null: false
    t.datetime "updated_at", null: false
    t.index ["principal", "key_digest"], name: "index_agent_write_receipts_on_principal_and_key_digest", unique: true
  end

  create_table "bans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["ip_address"], name: "index_bans_on_ip_address"
    t.index ["user_id"], name: "index_bans_on_user_id"
  end

  create_table "boosts", force: :cascade do |t|
    t.integer "booster_id", null: false
    t.string "content", limit: 16, null: false
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booster_id"], name: "index_boosts_on_booster_id"
    t.index ["message_id"], name: "index_boosts_on_message_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "connected_at"
    t.integer "connections", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "involvement", default: "mentions"
    t.integer "room_id", null: false
    t.datetime "unread_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["room_id", "created_at"], name: "index_memberships_on_room_id_and_created_at"
    t.index ["room_id", "user_id"], name: "index_memberships_on_room_id_and_user_id", unique: true
    t.index ["room_id"], name: "index_memberships_on_room_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "agent_revision", default: 1, null: false
    t.string "client_message_id", null: false
    t.datetime "created_at", null: false
    t.integer "creator_id", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_messages_on_creator_id"
    t.index ["room_id"], name: "index_messages_on_room_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key"
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.string "p256dh_key"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["endpoint", "p256dh_key", "auth_key"], name: "idx_on_endpoint_p256dh_key_auth_key_7553014576"
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.string "name"
    t.string "type", null: false
    t.datetime "updated_at", null: false
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "query", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_searches_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.text "bio"
    t.string "bot_token"
    t.datetime "created_at", null: false
    t.string "email_address"
    t.string "name", null: false
    t.boolean "native_agent", default: false, null: false
    t.string "password_digest"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["bot_token"], name: "index_users_on_bot_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_webhooks_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_actions", "agent_invocations", column: "invocation_id"
  add_foreign_key "agent_actions", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_actions", "agent_runs", column: "run_id"
  add_foreign_key "agent_actions", "rooms"
  add_foreign_key "agent_activities", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_activities", "agent_runs", column: "run_id"
  add_foreign_key "agent_artifacts", "agent_profiles", column: "publisher_profile_id"
  add_foreign_key "agent_artifacts", "agent_runs", column: "run_id"
  add_foreign_key "agent_artifacts", "rooms"
  add_foreign_key "agent_attention_reads", "users"
  add_foreign_key "agent_consumers", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_credentials", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_invocations", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_invocations", "rooms"
  add_foreign_key "agent_invocations", "users", column: "human_user_id"
  add_foreign_key "agent_message_tombstones", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_message_tombstones", "rooms"
  add_foreign_key "agent_operator_grants", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_operator_grants", "users"
  add_foreign_key "agent_participants", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_participants", "agent_runs", column: "run_id"
  add_foreign_key "agent_profiles", "users"
  add_foreign_key "agent_receipts", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_receipts", "rooms"
  add_foreign_key "agent_room_grants", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_room_grants", "rooms"
  add_foreign_key "agent_run_messages", "agent_runs", column: "run_id"
  add_foreign_key "agent_runs", "agent_profiles", column: "owner_profile_id"
  add_foreign_key "agent_runs", "agent_receipts", column: "outcome_receipt_id"
  add_foreign_key "agent_runs", "rooms"
  add_foreign_key "agent_uploads", "agent_profiles", column: "profile_id"
  add_foreign_key "agent_uploads", "rooms"
  add_foreign_key "bans", "users"
  add_foreign_key "boosts", "messages"
  add_foreign_key "messages", "rooms"
  add_foreign_key "messages", "users", column: "creator_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "searches", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "webhooks", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "message_search_index", "fts5", ["body", "tokenize=porter"]
  execute "CREATE TRIGGER agent_maintenance_audits_immutable_delete BEFORE DELETE ON agent_maintenance_audits BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END"
  execute "CREATE TRIGGER agent_maintenance_audits_immutable_update BEFORE UPDATE ON agent_maintenance_audits BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END"
  execute "CREATE TRIGGER agent_membership_delete AFTER DELETE ON memberships BEGIN\n  UPDATE agent_profiles SET authorization_version = authorization_version + 1 WHERE user_id = OLD.user_id;\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'room.membership.changed', 'room', CAST(OLD.room_id AS TEXT), OLD.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\nEND"
  execute "CREATE TRIGGER agent_membership_insert AFTER INSERT ON memberships BEGIN\n  UPDATE agent_profiles SET authorization_version = authorization_version + 1 WHERE user_id = NEW.user_id;\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'room.membership.changed', 'room', CAST(NEW.room_id AS TEXT), NEW.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\nEND"
  execute "CREATE TRIGGER agent_membership_update AFTER UPDATE OF room_id, user_id ON memberships BEGIN\n  UPDATE agent_profiles SET authorization_version = authorization_version + 1 WHERE user_id = OLD.user_id OR user_id = NEW.user_id;\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'room.membership.changed', 'room', CAST(OLD.room_id AS TEXT), OLD.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)\n  SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'room.membership.changed', 'room', CAST(NEW.room_id AS TEXT), NEW.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP\n  WHERE NEW.room_id != OLD.room_id;\nEND"
  execute "CREATE TRIGGER agent_message_created AFTER INSERT ON messages BEGIN\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, resource_revision, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'message.created', 'message', CAST(NEW.id AS TEXT), NEW.room_id, NEW.agent_revision, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\nEND"
  execute "CREATE TRIGGER agent_message_deleted AFTER DELETE ON messages BEGIN\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, resource_revision, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'message.deleted', 'message', CAST(OLD.id AS TEXT), OLD.room_id, OLD.agent_revision, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\nEND"
  execute "CREATE TRIGGER agent_message_edited AFTER UPDATE ON messages BEGIN\n  INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, resource_revision, actor_kind, created_at, updated_at)\n  VALUES(lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))), 'message.edited', 'message', CAST(NEW.id AS TEXT), NEW.room_id, NEW.agent_revision, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);\nEND"
  execute "CREATE TRIGGER agent_receipts_immutable_delete BEFORE DELETE ON agent_receipts BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END"
  execute "CREATE TRIGGER agent_receipts_immutable_update BEFORE UPDATE ON agent_receipts BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END"
  execute "CREATE TRIGGER agent_rich_text_revision AFTER UPDATE OF body ON action_text_rich_texts\nWHEN NEW.record_type = 'Message' BEGIN\n  UPDATE messages SET agent_revision = agent_revision + 1 WHERE id = NEW.record_id;\nEND"
end
