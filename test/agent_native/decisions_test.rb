require "test_helper"

class AgentNativeDecisionsTest < ActiveSupport::TestCase
  setup do
    Rails.configuration.x.agent_native.enabled = true
    @previous_dispatch = ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"]
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = "true"
    AgentNative::Instance.current.update!(recovery_required: false)
    @room, @human = rooms(:watercooler), users(:david)
    capabilities = { "modes" => [ "task" ], "supports_cancel" => true, "supports_pause" => false, "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] }
    manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => [], "capabilities" => capabilities, "action_types" => [ "analysis.approve" ] }
    @profile = AgentNative::Profile.provision!(name: "Reference", manifest: manifest)
    @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @profile.operator_grants.create!(user: @human)
    @run = AgentNative::Run.project_new!(@profile, { "room_id" => @room.id.to_s, "external_run_id" => SecureRandom.uuid,
      "title" => "Task", "state" => "running", "owner_generation" => 1, "source_revision" => 1,
      "context" => { "references" => [], "include_current_request" => false }, "reconciliation_reference" => "fixture" })
    @action = AgentNative::Action.propose!(@profile, { "run_id" => @run.id, "kind" => "approval", "operation" => "analysis.approve",
      "title" => "Review plan", "description" => "Approve this exact revision", "arguments" => { "version" => 1 }, "input_schema" => {},
      "subject_references" => [], "reviewer_user_ids" => [ @human.id.to_s ], "expires_at" => 5.minutes.from_now.iso8601 })
    @decision = { "proposal_digest" => @action.proposal_digest, "decision" => "approve", "input" => {} }
  end
  teardown do
    Rails.configuration.x.agent_native.enabled = false
    ENV["CAMPFIRE_AGENT_DISPATCH_ENABLED"] = @previous_dispatch
  end

  test "a human decision is immutable intent, not completion" do
    receipt = @action.decide!(@human, @decision)
    assert_equal "human_intent", receipt.kind
    assert_equal "running", @run.reload.state
    assert_raises(AgentNative::Error) { @action.decide!(@human, @decision) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { receipt.update!(result: "succeeded") }
    AgentNative::Contract.validate!("Receipt", receipt.wire.deep_stringify_keys)
  end

  test "changed proposal or revoked operator rejects approval" do
    @run.increment!(:version)
    assert_raises(AgentNative::Error) { @action.decide!(@human, @decision) }
    @profile.operator_grants.delete_all
    assert_raises(AgentNative::Error) { @action.decide!(@human, @decision) }
    assert_nil @action.reload.decision_receipt_id
  end

  test "cancel is a request and unsupported pause is rejected" do
    receipt = AgentNative::Control.request!(@run, @human, { "control" => "cancel", "expected_run_version" => @run.version })
    assert_equal "cancel_requested", receipt.result
    assert_equal "running", @run.reload.state
    assert_raises(AgentNative::Error) { AgentNative::Control.request!(@run, @human, { "control" => "pause", "expected_run_version" => @run.version }) }
  end

  test "outcomes require admission and preserve indeterminate results" do
    decision = @action.decide!(@human, @decision)
    input = { "kind" => "outcome", "subject" => { "type" => "action", "id" => @action.id }, "runtime_operation_id" => "op-1",
      "result" => "succeeded", "evidence" => [], "source_revision" => 2, "decision_receipt_id" => decision.id }
    assert_raises(AgentNative::Error) { AgentNative::Receipt.record_runtime!(@profile, input) }
    AgentNative::Receipt.record_runtime!(@profile, input.merge("kind" => "admission", "result" => "accepted", "source_revision" => 1))
    uncertain = AgentNative::Receipt.record_runtime!(@profile, input.merge("result" => "indeterminate"))
    assert_equal "indeterminate", uncertain.result
    AgentNative::Receipt.record_runtime!(@profile, input.merge("source_revision" => 3))
    assert_raises(AgentNative::Error) { AgentNative::Receipt.record_runtime!(@profile, input.merge("source_revision" => 4)) }
  end

  test "marking attention read does not resolve its action" do
    AgentNative::AttentionRead.create!(user: @human, item_id: @action.id, read: true)
    item = AgentNative::Attention.page(@human)[:items].find { |i| i[:id] == @action.id }
    assert item[:read]
    assert_equal "pending", @action.reload.state
  end

  test "stale proposals are excluded from attention" do
    @run.increment!(:version)

    assert_empty AgentNative::Attention.page(@human)[:items]
    assert_equal "pending", @action.reload.state
  end

  test "custom fields cannot introduce executable or remote schemas" do
    assert_raises(AgentNative::Error) { AgentNative::ActionInput.validate_schema!({ "$ref" => "https://example.test/schema" }) }
    assert_raises(AgentNative::Error) { AgentNative::ActionInput.validate!({ "type" => "object", "properties" => { "count" => { "type" => "integer", "maximum" => 3 } } }, { "count" => 4 }) }
  end

  test "one human approval cannot authorize multiple operation admissions" do
    decision = @action.decide!(@human, @decision)
    input = { "kind" => "admission", "subject" => { "type" => "action", "id" => @action.id },
      "runtime_operation_id" => "op-1", "result" => "accepted", "evidence" => [],
      "source_revision" => 1, "decision_receipt_id" => decision.id }
    first = AgentNative::Receipt.record_runtime!(@profile, input)
    assert_no_difference "AgentNative::Receipt.count" do
      assert_raises(AgentNative::Error) do
        AgentNative::Receipt.record_runtime!(@profile, input.merge("runtime_operation_id" => "op-2"))
      end
      assert_raises(AgentNative::Error) do
        AgentNative::Receipt.record_runtime!(@profile, input.merge("source_revision" => 2))
      end
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      AgentNative::Receipt.create!(first.attributes.except("id").merge("runtime_operation_id" => "op-3"))
    end
    outcome = AgentNative::Receipt.record_runtime!(@profile, input.merge("kind" => "outcome", "result" => "succeeded", "source_revision" => 2))
    assert_equal "succeeded", outcome.result
  end
end
