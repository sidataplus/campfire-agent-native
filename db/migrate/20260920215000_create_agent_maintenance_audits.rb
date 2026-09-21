class CreateAgentMaintenanceAudits < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_maintenance_audits, id: :string do |t|
      t.string :operation, null: false
      t.string :actor_id, null: false
      t.string :evidence_reference, null: false
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    reversible do |direction|
      direction.up do
        %w[agent_receipts agent_maintenance_audits].each do |table|
          execute "CREATE TRIGGER #{table}_immutable_update BEFORE UPDATE ON #{table} BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END;"
          execute "CREATE TRIGGER #{table}_immutable_delete BEFORE DELETE ON #{table} BEGIN SELECT RAISE(ABORT, 'Immutable audit record'); END;"
        end
      end
      direction.down do
        %w[agent_receipts agent_maintenance_audits].each do |table|
          execute "DROP TRIGGER IF EXISTS #{table}_immutable_update"
          execute "DROP TRIGGER IF EXISTS #{table}_immutable_delete"
        end
      end
    end
  end
end
