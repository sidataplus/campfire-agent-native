require "test_helper"

class AgentNativeEventsTest < ActiveSupport::TestCase
  test "bulk message changes and rich text edits commit events transactionally" do
    message = Message.first!
    before = AgentNative::Event.count
    Message.transaction do
      message.update!(body: "Transaction rollback")
      raise ActiveRecord::Rollback
    end
    assert_equal before, AgentNative::Event.count
    assert_difference -> { AgentNative::Event.count } do
      Message.where(id: message.id).update_all(updated_at: Time.current)
    end
    revision = message.reload.agent_revision
    message.rich_text_body.update!(body: "Direct rich text edit")
    assert_operator message.reload.agent_revision, :>, revision
  end

  test "ordinary chat does not create invocations" do
    assert_no_difference -> { AgentNative::Invocation.count } do
      Message.create!(room: rooms(:watercooler), creator: users(:david), body: "@reference start research")
    end
  end

  test "membership updates fence both users and publish both room boundaries" do
    manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => [],
      "action_types" => [], "capabilities" => { "modes" => [ "notification" ], "supports_cancel" => false,
        "supports_pause" => false, "supports_resume" => false, "supports_followup" => false,
        "supports_artifacts" => false, "activity_kinds" => [] } }
    old_profile = AgentNative::Profile.provision!(name: "Old member", manifest: manifest)
    new_profile = AgentNative::Profile.provision!(name: "New member", manifest: manifest)
    old_room, new_room = rooms(:watercooler), rooms(:pets)
    membership = Membership.create!(room: old_room, user: old_profile.user)
    old_version = old_profile.reload.authorization_version
    new_version = new_profile.reload.authorization_version
    before = AgentNative::Event.where(kind: "room.membership.changed").count

    membership.update!(room: new_room, user: new_profile.user)

    assert_equal old_version + 1, old_profile.reload.authorization_version
    assert_equal new_version + 1, new_profile.reload.authorization_version
    rooms = AgentNative::Event.where(kind: "room.membership.changed").order(:id).last(2).map(&:room_id)
    assert_equal [ old_room.id, new_room.id ].sort, rooms.sort
    assert_equal before + 2, AgentNative::Event.where(kind: "room.membership.changed").count
  end
end
