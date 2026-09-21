require "test_helper"

class AgentNativeHumanAttentionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @previous_dispatch = ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"]
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = "true"
    AgentNative::Instance.current.update!(recovery_required: false)
    @room, @human = rooms(:watercooler), users(:david)
    capabilities = { "modes" => [ "task" ], "supports_cancel" => true, "supports_pause" => false,
      "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] }
    manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => [],
      "capabilities" => capabilities, "action_types" => [ "analysis.approve" ] }
    @profile = AgentNative::Profile.provision!(name: "Human attention", manifest: manifest)
    @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @profile.operator_grants.create!(user: @human)
    @run = AgentNative::Run.project_new!(@profile, { "room_id" => @room.id.to_s, "external_run_id" => SecureRandom.uuid,
      "title" => "Task", "state" => "running", "owner_generation" => 1, "source_revision" => 1,
      "context" => { "references" => [], "include_current_request" => false }, "reconciliation_reference" => "fixture" })
    @action = AgentNative::Action.propose!(@profile, { "run_id" => @run.id, "kind" => "approval", "operation" => "analysis.approve",
      "title" => "Review plan", "description" => "Approve this exact revision", "arguments" => { "version" => 1 },
      "input_schema" => {}, "subject_references" => [], "reviewer_user_ids" => [ @human.id.to_s ],
      "expires_at" => 5.minutes.from_now.iso8601 })
    sign_in @human
  end

  teardown do
    Rails.configuration.x.agent_native.enabled = false
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = @previous_dispatch
  end

  test "attention read is idempotent, returns status, and keeps the marker race safe" do
    key = SecureRandom.uuid
    headers = { "Content-Type" => "application/json", "Accept" => "application/json", "Idempotency-Key" => key }
    payload = { "read" => true }.to_json

    post "/agent/attention/#{@action.id}/read", params: payload, headers: headers
    assert_response :created
    assert_equal({ "ok" => true }, response.parsed_body)
    assert_equal 1, AgentNative::AttentionRead.where(user: @human, item_id: @action.id).count

    assert_no_difference -> { AgentNative::AttentionRead.count } do
      post "/agent/attention/#{@action.id}/read", params: payload, headers: headers
    end
    assert_response :created
    assert_equal({ "ok" => true }, response.parsed_body)

    post "/agent/attention/#{@action.id}/read", params: { "read" => false }.to_json, headers: headers
    assert_response :conflict
    assert AgentNative::AttentionRead.find_by!(user: @human, item_id: @action.id).read
  end

  test "human controls require the current run etag" do
    headers = { "Content-Type" => "application/json", "Accept" => "application/json", "Idempotency-Key" => SecureRandom.uuid }
    payload = { "control" => "cancel", "expected_run_version" => @run.version }.to_json

    post "/agent/runs/#{@run.id}/controls", params: payload, headers: headers
    assert_response :precondition_required

    headers["If-Match"] = %Q("#{@run.id}:#{@run.version}")
    post "/agent/runs/#{@run.id}/controls", params: payload, headers: headers
    assert_response :created
    assert_equal "running", @run.reload.state
  end

  test "a completed control request replays after the run version advances" do
    headers = { "Content-Type" => "application/json", "Accept" => "application/json",
      "Idempotency-Key" => SecureRandom.uuid, "If-Match" => %Q("#{@run.id}:#{@run.version}") }
    payload = { "control" => "cancel", "expected_run_version" => @run.version }.to_json

    post "/agent/runs/#{@run.id}/controls", params: payload, headers: headers
    assert_response :created
    original = response.parsed_body.fetch("resource").fetch("id")

    @run.update!(version: @run.version + 1)
    post "/agent/runs/#{@run.id}/controls", params: payload, headers: headers
    assert_response :created
    assert_equal original, response.parsed_body.fetch("resource").fetch("id")
    assert response.parsed_body.fetch("replayed")
  end
end
