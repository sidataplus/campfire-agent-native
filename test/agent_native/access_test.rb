require "test_helper"

class AgentNativeAccessTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @room = rooms(:watercooler)
    @manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => AgentNative::Contract::DEFINITIONS.fetch("Scope").fetch("enum"), "action_types" => [],
      "capabilities" => { "modes" => [ "notification", "interactive", "task" ], "supports_cancel" => true, "supports_pause" => false, "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] } }
    @profile = AgentNative::Profile.provision!(name: "Reference", manifest: @manifest)
    @grant = @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @credential, @token = AgentNative::Credential.issue!(profile: @profile, scopes: @manifest["requested_scopes"])
    @headers = { "Authorization" => "Bearer #{@token}", "Idempotency-Key" => SecureRandom.uuid }
  end
  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "native identities cannot inherit open rooms or legacy authentication" do
    assert_equal [ @room.id ], @profile.user.rooms.ids
    assert_nil User.authenticate_bot("#{@profile.user_id}-")
    assert_nil User.authenticate_bot("#{@profile.user_id}-anything")
    assert_raises(ActiveRecord::RecordInvalid) { @profile.user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1") }
    assert_raises(ActiveRecord::RecordInvalid) { @profile.user.update!(bot_token: "abc") }
    rooms(:designers).becomes(Rooms::Open).update!(type: "Rooms::Open")
    assert_not @profile.user.rooms.exists?(rooms(:designers).id)
  end

  test "notification-only credential writes idempotently but cannot read" do
    @credential.update!(scopes: [ "messages:write" ])
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

  test "idempotency compares canonical JSON rather than key insertion order" do
    uuid = SecureRandom.uuid
    path = "/api/agent/v1/rooms/#{@room.id}/messages"
    post path, params: { body_text: "hello", client_message_id: uuid }, headers: @headers, as: :json
    assert_response :created
    id = response.parsed_body.fetch("resource").fetch("id")
    post path, params: { client_message_id: uuid, body_text: "hello" }, headers: @headers, as: :json
    assert_response :created
    assert response.parsed_body["replayed"]
    assert_equal id, response.parsed_body.fetch("resource").fetch("id")
  end

  test "delete replay retains current authorization and never creates another effect" do
    message = Message.create!(room: @room, creator: @profile.user, body: "delete me")
    path = "/api/agent/v1/messages/#{message.id}"
    headers = @headers.merge("If-Match" => %Q("#{message.id}:#{message.agent_revision}"))
    delete path, headers: headers
    assert_response :ok
    assert_equal false, response.parsed_body.fetch("replayed")
    resource = response.parsed_body.fetch("resource")
    assert_equal({ "type" => "message", "id" => message.id.to_s }, resource)
    assert_no_difference [ "Message.count", "AgentNative::MessageTombstone.count", "AgentNative::WriteReceipt.count" ] do
      delete path, headers: headers
    end
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("replayed")
    assert_equal resource, response.parsed_body.fetch("resource")
    delete path, headers: headers.merge("Idempotency-Key" => SecureRandom.uuid)
    assert_response :not_found
    @grant.destroy!
    delete path, headers: headers
    assert_response :not_found
  end

  test "token scopes cannot outlive the approved manifest" do
    @profile.update!(manifest: @manifest.merge("requested_scopes" => [ "rooms:read" ]))
    get "/api/agent/v1/rooms/#{@room.id}/messages", headers: @headers
    assert_response :forbidden
    get "/api/agent/v1/self", headers: @headers
    assert_equal [ "rooms:read" ], response.parsed_body.fetch("effective_scopes")
  end

  test "native attachment download rechecks room access and rejects signed URLs" do
    message = Message.create!(room: @room, creator: @profile.user, body: "file")
    message.attachment.attach(io: StringIO.new("private bytes"), filename: "result.txt", content_type: "text/plain")
    path = "/api/agent/v1/messages/#{message.id}/attachments/#{message.attachment_attachment.id}/content"
    get path, headers: @headers
    assert_response :success
    assert_equal "private bytes", response.body
    sign_in users(:david)
    get rails_blob_path(message.attachment.blob, only_path: true)
    assert_response :not_found
    @grant.destroy!
    get path, headers: @headers
    assert_response :not_found
  end

  test "history grant excludes earlier messages and malformed numeric IDs fail closed" do
    message = Message.create!(room: @room, creator: users(:david), body: "older")
    @grant.update!(history_policy: "since_grant", created_at: 1.minute.from_now)
    get "/api/agent/v1/messages/#{message.id}", headers: @headers
    assert_response :not_found
    get "/api/agent/v1/rooms/#{@room.id}suffix/messages", headers: @headers
    assert_response :unprocessable_entity
  end

  test "schema patterns reject newline suffixes and missing timestamp offsets" do
    refute AgentNative::Contract.valid?({ "type" => "string", "pattern" => "^[0-9]+$" }, "123\ninjection")
    refute AgentNative::Contract.valid?({ "type" => "string", "format" => "date-time" }, "2026-09-20T12:00:00")
  end

  test "UUID format accepts five groups and rejects malformed four-group values" do
    schema = { "type" => "string", "format" => "uuid" }
    assert AgentNative::Contract.valid?(schema, "01234567-89ab-cdef-0123-456789abcdef")
    assert AgentNative::Contract.valid?(schema, "01234567-89AB-CDEF-0123-456789ABCDEF")
    refute AgentNative::Contract.valid?(schema, "01234567-89ab-cdef-456789abcdef")
    refute AgentNative::Contract.valid?(schema, "01234567-89ab-cdef-0123-456789abcdef\n")
  end
end
