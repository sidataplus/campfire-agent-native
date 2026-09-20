require "test_helper"

class AgentNativeAccessTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @room = rooms(:watercooler)
    @manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum"), "action_types" => [],
      "capabilities" => { "modes" => ["notification", "interactive", "task"], "supports_cancel" => true, "supports_pause" => false, "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] } }
    @profile = AgentNative::Profile.provision!(name: "Reference", manifest: @manifest)
    @grant = @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @credential, @token = AgentNative::Credential.issue!(profile: @profile, scopes: @manifest["requested_scopes"])
    @headers = { "Authorization" => "Bearer #{@token}", "Idempotency-Key" => SecureRandom.uuid }
  end
  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "native identities cannot inherit open rooms or legacy authentication" do
    assert_equal [@room.id], @profile.user.rooms.ids
    assert_nil User.authenticate_bot("#{@profile.user_id}-")
    assert_nil User.authenticate_bot("#{@profile.user_id}-anything")
    assert_raises(ActiveRecord::RecordInvalid) { @profile.user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1") }
    assert_raises(ActiveRecord::RecordInvalid) { @profile.user.update!(bot_token: "abc") }
    rooms(:designers).becomes(Rooms::Open).update!(type: "Rooms::Open")
    assert_not @profile.user.rooms.exists?(rooms(:designers).id)
  end

  test "notification-only credential writes idempotently but cannot read" do
    @credential.update!(scopes: ["messages:write"])
    payload = { body_text: "Status <script>not executable</script>", client_message_id: SecureRandom.uuid }
    assert_difference -> { Message.count }, 1 do
      2.times { post "/api/agent/v1/rooms/#{@room.id}/messages", params: payload, headers: @headers, as: :json; assert_response :created }
    end
    assert response.parsed_body["replayed"]
    get "/api/agent/v1/rooms/#{@room.id}/messages", headers: @headers
    assert_response :forbidden
    post "/api/agent/v1/rooms/#{@room.id}/messages", params: payload.merge(body_text: "different"), headers: @headers, as: :json
    assert_response :conflict
  end

  test "rooms require current grant and token revocation applies to replay" do
    get "/api/agent/v1/rooms/#{rooms(:designers).id}/messages", headers: @headers
    assert_response :not_found
    @credential.update!(revoked_at: Time.current)
    get "/api/agent/v1/self", headers: @headers
    assert_response :unauthorized
  end

  test "human cookies never substitute for bearer authentication" do
    sign_in users(:david)
    get "/api/agent/v1/self"
    assert_response :unauthorized
  end

  test "schema validation rejects unknown fields and excessive paging" do
    post "/api/agent/v1/rooms/#{@room.id}/messages", params: { body_text: "x", client_message_id: SecureRandom.uuid, creator_id: users(:david).id }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    get "/api/agent/v1/rooms/#{@room.id}/messages?limit=101", headers: @headers
    assert_response :unprocessable_entity
  end

  test "writes enforce own-message policy and If-Match" do
    message = Message.create!(room: @room, creator: @profile.user, body: "before")
    patch "/api/agent/v1/messages/#{message.id}", params: { body_text: "after", expected_revision: 1 }, headers: @headers, as: :json
    assert_response :precondition_required
    patch "/api/agent/v1/messages/#{message.id}", params: { body_text: "after", expected_revision: 1 }, headers: @headers.merge("If-Match" => %Q("#{message.id}:1")), as: :json
    assert_response :success
    assert_equal "after", message.reload.plain_text_body
  end
end
