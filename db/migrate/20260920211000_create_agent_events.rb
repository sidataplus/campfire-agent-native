class CreateAgentEvents < ActiveRecord::Migration[8.2]
  def up
    create_table :agent_events do |t|
      t.string :event_uuid, null: false
      t.string :kind, null: false
      t.string :resource_type, null: false
      t.string :resource_id, null: false
      t.integer :room_id
      t.string :profile_id
      t.string :actor_kind, default: "system", null: false
      t.string :actor_id
      t.integer :resource_revision
      t.timestamps
    end
    add_index :agent_events, :event_uuid, unique: true
    add_index :agent_events, [ :profile_id, :id ]
    add_index :agent_events, [ :room_id, :id ]
    create_table :agent_consumers, id: :string do |t|
      t.string :profile_id, null: false
      t.string :name, null: false
      t.json :event_types, default: [], null: false
      t.json :room_ids, default: [], null: false
      t.integer :enrollment_floor, default: 0, null: false
      t.integer :checkpoint, default: 0, null: false
      t.integer :delivered, default: 0, null: false
      t.integer :authorization_version, null: false
      t.string :stream_epoch, null: false
      t.timestamps
    end
    add_index :agent_consumers, [ :profile_id, :name ], unique: true
    add_foreign_key :agent_consumers, :agent_profiles, column: :profile_id
    create_table :agent_invocations, id: :string do |t|
      t.string :profile_id, null: false
      t.references :room, null: false, foreign_key: true
      t.references :human_user, null: false, foreign_key: { to_table: :users }
      t.json :source, null: false
      t.text :normalized_input, null: false
      t.json :context, null: false
      t.string :run_id
      t.string :source_digest, null: false
      t.datetime :admission_expires_at, null: false
      t.string :disposition, default: "pending", null: false
      t.string :runtime_operation_id
      t.string :stream_epoch, null: false
      t.integer :version, default: 1, null: false
      t.timestamps
    end
    add_foreign_key :agent_invocations, :agent_profiles, column: :profile_id
    add_index :agent_invocations, [ :profile_id, :runtime_operation_id ], unique: true
    uuid = "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6)))"
    %w[INSERT UPDATE DELETE].each do |operation|
      row = operation == "DELETE" ? "OLD" : "NEW"
      kind = { "INSERT" => "created", "UPDATE" => "edited", "DELETE" => "deleted" }.fetch(operation)
      execute <<~SQL
        CREATE TRIGGER agent_message_#{kind} AFTER #{operation} ON messages BEGIN
          INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, resource_revision, actor_kind, created_at, updated_at)
          VALUES(#{uuid}, 'message.#{kind}', 'message', CAST(#{row}.id AS TEXT), #{row}.room_id, #{row}.agent_revision, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        END;
      SQL
    end
    execute <<~SQL
      CREATE TRIGGER agent_rich_text_revision AFTER UPDATE OF body ON action_text_rich_texts
      WHEN NEW.record_type = 'Message' BEGIN
        UPDATE messages SET agent_revision = agent_revision + 1 WHERE id = NEW.record_id;
      END;
    SQL
    %w[INSERT DELETE].each do |operation|
      row = operation == "DELETE" ? "OLD" : "NEW"
      execute <<~SQL
        CREATE TRIGGER agent_membership_#{operation.downcase} AFTER #{operation} ON memberships BEGIN
          UPDATE agent_profiles SET authorization_version = authorization_version + 1 WHERE user_id = #{row}.user_id;
          INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)
          VALUES(#{uuid}, 'room.membership.changed', 'room', CAST(#{row}.room_id AS TEXT), #{row}.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        END;
      SQL
    end
    execute <<~SQL
      CREATE TRIGGER agent_membership_update AFTER UPDATE OF room_id, user_id ON memberships BEGIN
        UPDATE agent_profiles SET authorization_version = authorization_version + 1
        WHERE user_id = OLD.user_id OR user_id = NEW.user_id;
        INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)
        VALUES(#{uuid}, 'room.membership.changed', 'room', CAST(OLD.room_id AS TEXT), OLD.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        INSERT INTO agent_events(event_uuid, kind, resource_type, resource_id, room_id, actor_kind, created_at, updated_at)
        SELECT #{uuid}, 'room.membership.changed', 'room', CAST(NEW.room_id AS TEXT), NEW.room_id, 'system', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        WHERE NEW.room_id != OLD.room_id;
      END;
    SQL
  end

  def down
    %w[agent_message_created agent_message_edited agent_message_deleted agent_rich_text_revision agent_membership_insert agent_membership_delete agent_membership_update].each { |name| execute "DROP TRIGGER IF EXISTS #{name}" }
    drop_table :agent_invocations
    drop_table :agent_consumers
    drop_table :agent_events
  end
end
