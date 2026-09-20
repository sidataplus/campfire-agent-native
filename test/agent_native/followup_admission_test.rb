require "test_helper"

class AgentNativeFollowupAdmissionTest < ActiveSupport::TestCase
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @previous_dispatch = ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"]
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = "true"
    AgentNative::Instance.current.update!(recovery_required: false)
    @room, @human = rooms(:watercooler), users(:david)
    capabilities = { "modes" => [ "task" ], "supports_cancel" => true, "supports_pause" => false,
      "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] }
    manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => [],
      "capabilities" => capabilities, "action_types" => [] }
    @profile = AgentNative::Profile.provision!(name: "Reference", manifest: manifest)
    @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @profile.operator_grants.create!(user: @human)
    @context = { "references" => [], "include_current_request" => false }
    @run = AgentNative::Run.project_new!(@profile, { "room_id" => @room.id.to_s, "external_run_id" => SecureRandom.uuid,
      "title" => "Task", "state" => "running", "owner_generation" => 1, "source_revision" => 1,
      "context" => @context, "reconciliation_reference" => "fixture" })
    @message = @run.run_messages.create!(author_kind: "human", author_id: @human.id.to_s,
      body_text: "Use narrower criteria", client_message_id: SecureRandom.uuid)
    input = { "profile_id" => @profile.id, "body_text" => @message.body_text, "client_message_id" => SecureRandom.uuid, "context" => @context }
    @invocation = AgentNative::Invocation.submit!(profile: @profile, human: @human, room: @room, input: input, run_id: @run.id,
      source: { "kind" => "run_message", "id" => @message.id, "revision" => @message.revision, "source_room_id" => @room.id.to_s })
    @admission = { "source_digest" => @invocation.source_digest, "disposition" => "admitted", "runtime_operation_id" => "followup-1" }
  end

  teardown do
    Rails.configuration.x.agent_native.enabled = false
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = @previous_dispatch
  end

  test "unchanged followup is admitted for its exact run" do
    @invocation.admit!(@admission)
    assert_equal "admitted", @invocation.reload.disposition
  end

  test "completed run rejects a previously pending followup" do
    @run.project!(@profile, { "state" => "completed", "owner_generation" => 1, "source_revision" => 2 })
    assert_raises(AgentNative::Error) { @invocation.admit!(@admission) }
    assert_equal "pending", @invocation.reload.disposition
  end

  test "modified or deleted source cannot be admitted" do
    @message.update!(body_text: "Different instruction", revision: 2)
    assert_raises(AgentNative::Error) { @invocation.admit!(@admission) }
    @message.destroy!
    assert_raises(AgentNative::Error) { @invocation.admit!(@admission) }
  end

  test "recovery-fenced run cannot accept a pending followup" do
    @run.update!(needs_reconciliation: true)
    assert_raises(AgentNative::Error) { @invocation.admit!(@admission) }
    assert_equal "pending", @invocation.reload.disposition
  end
end
