require "test_helper"

class AgentNativeEventAccessTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    AgentNative::Instance.current.update!(recovery_required: false)
    @room = rooms(:watercooler)
    @scopes = AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum")
    capabilities = { "modes" => [ "interactive" ], "supports_cancel" => false, "supports_pause" => false,
      "supports_resume" => false, "supports_followup" => false, "supports_artifacts" => false, "activity_kinds" => [ "analysis" ] }
    @manifest = { "name" => "Events", "protocol_version" => "1", "requested_scopes" => @scopes,
      "capabilities" => capabilities, "action_types" => [] }
    @profile = AgentNative::Profile.provision!(name: "Events", manifest: @manifest)
    @grant = @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    _, token = AgentNative::Credential.issue!(profile: @profile, scopes: @scopes)
    @headers = { "Authorization" => "Bearer #{token}" }
    @consumer = AgentNative::Consumer.create!(profile: @profile, name: "test", room_ids: [], event_types: [],
      authorization_version: @profile.reload.authorization_version, stream_epoch: AgentNative::Instance.current.stream_epoch)
    @consumer.reset_to_present!
  end

  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "events committed after enrollment are not lost to rounded database timestamps" do
    message = Message.create!(room: @room, creator: users(:david), body: "fresh")
    event = AgentNative::Event.where(resource_type: "message", resource_id: message.id.to_s).last!
    event.update_columns(created_at: @grant.created_at.change(usec: 0))
    get "/api/agent/v1/events", params: { consumer_id: @consumer.id, cursor: @consumer.cursor }, headers: @headers
    assert_response :ok
    assert_includes response.parsed_body.fetch("events").map { |item| item.fetch("id") }, event.event_uuid
  end

  test "message events obey reduced manifest scopes" do
    @profile.update!(manifest: @manifest.merge("requested_scopes" => @scopes - [ "messages:read" ]))
    @consumer.reset_to_present!
    message = Message.create!(room: @room, creator: users(:david), body: "private")
    get "/api/agent/v1/events", params: { consumer_id: @consumer.id, cursor: @consumer.cursor }, headers: @headers
    assert_response :ok
    refute response.parsed_body.fetch("events").any? { |item| item.fetch("resource")["id"] == message.id.to_s }
  end

  test "new room grants invalidate a consumer until explicit resynchronization" do
    old_cursor = @consumer.cursor
    @profile.room_grants.create!(room: rooms(:designers), history_policy: "all_authorized")
    get "/api/agent/v1/events", params: { consumer_id: @consumer.id, cursor: old_cursor }, headers: @headers
    assert_response :conflict
    assert_equal "ACCESS_CHANGED", response.parsed_body.fetch("code")
  end

  test "recovery quarantine blocks replay without advancing the consumer" do
    AgentNative::Instance.current.update!(recovery_required: true)
    previous = @consumer.delivered
    Message.create!(room: @room, creator: users(:david), body: "quarantined")
    get "/api/agent/v1/events", params: { consumer_id: @consumer.id, cursor: @consumer.cursor }, headers: @headers
    assert_response :conflict
    assert_equal "RECOVERY_REQUIRED", response.parsed_body.fetch("code")
    assert_equal previous, @consumer.reload.delivered
  end

  test "run events are limited to profiles that can see the run" do
    outsider_manifest = @manifest.merge("name" => "Outsider")
    outsider = AgentNative::Profile.provision!(name: "Outsider", manifest: outsider_manifest)
    outsider.room_grants.create!(room: @room, history_policy: "all_authorized")
    _, outsider_token = AgentNative::Credential.issue!(profile: outsider, scopes: @scopes)
    outsider_consumer = AgentNative::Consumer.create!(profile: outsider, name: "test", room_ids: [], event_types: [],
      authorization_version: outsider.reload.authorization_version, stream_epoch: AgentNative::Instance.current.stream_epoch)
    outsider_consumer.reset_to_present!

    run = AgentNative::Run.create!(room: @room, owner_profile: @profile, runtime_id: @profile.runtime_id,
      external_run_id: SecureRandom.uuid, title: "Private run", state: "running", owner_generation: 1,
      source_revision: 1, context: { "references" => [], "include_current_request" => false },
      last_reported_at: Time.current)
    AgentNative::Event.publish!(kind: "run.created", resource: run, room: @room, actor: @profile)
    run.run_messages.create!(author_kind: "agent", author_id: @profile.id, body_text: "Private detail", client_message_id: SecureRandom.uuid)
    AgentNative::Activity.report!(run, @profile, { "operation_id" => "private-step", "kind" => "analysis",
      "state" => "completed", "summary" => "Private activity", "evidence" => [], "owner_generation" => 1,
      "source_revision" => 1 })

    get "/api/agent/v1/events", params: { consumer_id: outsider_consumer.id, cursor: outsider_consumer.cursor },
      headers: { "Authorization" => "Bearer #{outsider_token}" }
    assert_response :ok
    refute response.parsed_body.fetch("events").any? { |event| %w[run run_message activity].include?(event.fetch("resource").fetch("type")) }
  end
end
