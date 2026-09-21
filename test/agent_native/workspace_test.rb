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

  test "read-only render never accepts an agent bearer in place of a human" do
    get "/agent/workspace", headers: { "Authorization" => "Bearer acn_#{'x' * 43}" }
    assert_response :forbidden
  end
end
