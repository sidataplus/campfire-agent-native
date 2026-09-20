class CreateAgentNotifications < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_notifications, id: :string do |t|
      t.string :event_uuid, null: false
      t.integer :user_id, null: false
      t.integer :subscription_id, null: false
      t.integer :room_id, null: false
      t.string :action_id
      t.string :run_id
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :last_error_class
      t.datetime :ready_at, null: false
      t.timestamps
    end
    add_index :agent_notifications, [ :event_uuid, :subscription_id ], unique: true
    add_index :agent_notifications, [ :state, :ready_at ]
  end
end
