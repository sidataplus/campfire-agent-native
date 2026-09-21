require "test_helper"

class AgentNativeMalformedDeleteTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    manifest = { "name" => "Delete test", "protocol_version" => "1", "requested_scopes" => [ "messages:edit_own" ],
      "capabilities" => { "modes" => [ "notification" ], "supports_cancel" => false, "supports_pause" => false,
        "supports_resume" => false, "supports_followup" => false, "supports_artifacts" => false, "activity_kinds" => [] }, "action_types" => [] }
    profile = AgentNative::Profile.provision!(name: "Delete test", manifest: manifest)
    _, token = AgentNative::Credential.issue!(profile: profile, scopes: [ "messages:edit_own" ])
    @headers = { "Authorization" => "Bearer #{token}", "Idempotency-Key" => SecureRandom.uuid, "If-Match" => '"invalid:1"' }
  end

  teardown { Rails.configuration.x.agent_native.enabled = false }

  test "delete rejects malformed identifiers before existence and tombstone queries" do
    %w[1suffix 1-- 1=1].each do |id|
      assert_no_difference [ "Message.count", "AgentNative::WriteReceipt.count" ] do
        delete "/api/agent/v1/messages/#{id}", headers: @headers
      end
      assert_response :unprocessable_entity
      assert_equal "VALIDATION_FAILED", response.parsed_body.fetch("code")
    end
  end
end
