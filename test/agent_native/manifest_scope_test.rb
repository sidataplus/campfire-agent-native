require "test_helper"

class AgentNativeManifestScopeTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @room = rooms(:watercooler)
    @direct = rooms(:david_and_jason)
    @scopes = AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum")
    capabilities = { "modes" => [ "interactive" ], "supports_cancel" => false, "supports_pause" => false,
      "supports_resume" => false, "supports_followup" => false, "supports_artifacts" => false, "activity_kinds" => [] }
    @manifest = { "name" => "Scoped", "protocol_version" => "1", "requested_scopes" => @scopes,
      "capabilities" => capabilities, "action_types" => [] }
    @profile = AgentNative::Profile.provision!(name: "Scoped", manifest: @manifest)
    [ @room, @direct ].each { |room| @profile.room_grants.create!(room: room, history_policy: "all_authorized") }
    _, token = AgentNative::Credential.issue!(profile: @profile, scopes: @scopes)
    @headers = { "Authorization" => "Bearer #{token}" }
  end

  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "room lists hide direct rooms when manifest removes DM access" do
    @profile.update!(manifest: @manifest.merge("requested_scopes" => @scopes - [ "dms:read" ]))
    get "/api/agent/v1/rooms", headers: @headers
    assert_response :ok
    ids = response.parsed_body.fetch("items").map { |room| room.fetch("id") }
    assert_includes ids, @room.id.to_s
    assert_not_includes ids, @direct.id.to_s
  end

  test "attachment metadata disappears when the approved scope is removed" do
    message = Message.create!(room: @room, creator: @profile.user, body: "Result")
    message.attachment.attach(io: StringIO.new("private bytes"), filename: "result.txt", content_type: "text/plain")
    @profile.update!(manifest: @manifest.merge("requested_scopes" => @scopes - [ "attachments:read" ]))
    get "/api/agent/v1/messages/#{message.id}", headers: @headers
    assert_response :ok
    assert_empty response.parsed_body.fetch("attachments")
  end
end
