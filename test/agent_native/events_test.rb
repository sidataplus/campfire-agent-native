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
end
