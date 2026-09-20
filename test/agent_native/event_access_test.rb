require "test_helper"

class AgentNativeEventAccessTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @room = rooms(:watercooler)
    @scopes = AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum")
    capabilities = { "modes" => [ "interactive" ], "supports_cancel" => false, "supports_pause" => false,
      "supports_resume" => false, "supports_followup" => false, "supports_artifacts" => false, "activity_kinds" => [] }
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
    assert_equal "access_changed", response.parsed_body.fetch("code")
  end
end
