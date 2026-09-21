require "test_helper"

class AgentNativeWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    sign_in users(:david)
  end
  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "workspace is human authenticated and does not activate work" do
    assert_no_difference -> { AgentNative::Invocation.count } do
      get "/agent/workspace"
      assert_response :success
      assert_select "h1", "Agent workspace"
      assert_select "input[name=request_key]"
    end
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "room outsider cannot download a native artifact" do
    artifact = AgentNative::Artifact.new(id: SecureRandom.uuid)
    get "/agent/workspace/artifacts/#{artifact.id}/content"
    assert_response :not_found
  end

  test "admin panel is unavailable to nonadministrators" do
    sign_in users(:jz)
    get "/agent/admin"
    assert_response :forbidden
  end

  test "admin rejects a manifest without a name before provisioning" do
    manifest = {
      "protocol_version" => "1",
      "requested_scopes" => [],
      "action_types" => [],
      "capabilities" => {
        "modes" => [ "notification" ], "supports_cancel" => false, "supports_pause" => false,
        "supports_resume" => false, "supports_followup" => false, "supports_artifacts" => false,
        "activity_kinds" => []
      }
    }

    assert_no_difference -> { AgentNative::Profile.count } do
      post "/agent/admin", params: { manifest: JSON.generate(manifest) }
    end
    assert_response :unprocessable_entity
  end

  test "workspace field coercion accepts only canonical primitive strings" do
    controller = AgentNative::WorkspaceController.new
    schema = { "properties" => {
      "count" => { "type" => "integer" }, "ratio" => { "type" => "number" }, "enabled" => { "type" => "boolean" }
    } }

    assert_equal({ "count" => 2, "ratio" => 1.5, "enabled" => false },
      controller.send(:typed_fields, schema, { "count" => "2", "ratio" => "1.5", "enabled" => "false" }))
    assert_raises(AgentNative::Error) { controller.send(:typed_fields, schema, { "count" => "2.0" }) }
    assert_raises(AgentNative::Error) { controller.send(:typed_fields, schema, { "enabled" => "yes" }) }
  end

  test "read-only render never accepts an agent bearer in place of a human" do
    get "/agent/workspace", headers: { "Authorization" => "Bearer acn_#{'x' * 43}" }
    assert_response :forbidden
  end
end
