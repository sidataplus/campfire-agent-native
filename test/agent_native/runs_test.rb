require "test_helper"

class AgentNativeRunsTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:watercooler)
    capabilities = { "modes" => [ "task" ], "supports_cancel" => true, "supports_pause" => false, "supports_resume" => false, "supports_followup" => true, "supports_artifacts" => true, "activity_kinds" => [] }
    manifest = { "name" => "Reference", "protocol_version" => "1", "requested_scopes" => [], "capabilities" => capabilities, "action_types" => [] }
    @profile = AgentNative::Profile.provision!(name: "Reference", manifest: manifest)
    @profile.room_grants.create!(room: @room, history_policy: "all_authorized")
    @input = { "room_id" => @room.id.to_s, "external_run_id" => SecureRandom.uuid, "title" => "Task", "state" => "running", "owner_generation" => 1,
      "source_revision" => 1, "context" => { "references" => [], "include_current_request" => false }, "reconciliation_reference" => "synthetic-existing-work" }
    @run = AgentNative::Run.project_new!(@profile, @input)
  end

  test "terminal runs cannot reopen and stale owners cannot write" do
    assert_raises(AgentNative::Error) { @run.project!(@profile, { "state" => "running", "owner_generation" => 2, "source_revision" => 2 }) }
    @run.project!(@profile, { "state" => "completed", "owner_generation" => 1, "source_revision" => 2 })
    assert_raises(AgentNative::Error) { @run.project!(@profile, { "state" => "running", "owner_generation" => 1, "source_revision" => 3 }) }
    assert_equal "completed", @run.reload.state
    AgentNative::Contract.validate!("Run", @run.wire.deep_stringify_keys)
  end

  test "completed activity operations cannot be changed" do
    input = { "operation_id" => "step-1", "kind" => "analysis", "state" => "completed", "summary" => "Finished",
      "evidence" => [], "owner_generation" => 1, "source_revision" => 1 }
    AgentNative::Activity.report!(@run, @profile, input)

    assert_raises(AgentNative::Error) do
      AgentNative::Activity.report!(@run, @profile, input.merge("state" => "running", "source_revision" => 2))
    end
  end

  test "terminal run updates persist and validate their outcome receipt" do
    receipt = AgentNative::Receipt.record_runtime!(@profile, {
      "kind" => "outcome", "subject" => { "type" => "run", "id" => @run.id },
      "runtime_operation_id" => "run-op-1", "result" => "succeeded", "evidence" => [],
      "owner_generation" => @run.owner_generation, "source_revision" => 2
    })

    @run.project!(@profile, { "state" => "completed", "owner_generation" => 1, "source_revision" => 2,
      "outcome_receipt_id" => receipt.id })

    assert_equal receipt.id, @run.reload.outcome_receipt_id
    AgentNative::Contract.validate!("Run", @run.wire.deep_stringify_keys)
  end

  test "run outcome receipt must belong to the projected run" do
    assert_raises(AgentNative::Error) do
      @run.project!(@profile, { "state" => "completed", "owner_generation" => 1, "source_revision" => 2,
        "outcome_receipt_id" => SecureRandom.uuid })
    end
    assert_equal "running", @run.reload.state
  end

  test "run conversations never become ordinary room messages" do
    other = AgentNative::Run.project_new!(@profile, @input.merge("external_run_id" => SecureRandom.uuid))
    assert_no_difference -> { Message.count } do
      @run.run_messages.create!(author_kind: "agent", author_id: @profile.id, body_text: "Specific to one task", client_message_id: SecureRandom.uuid)
    end
    assert_equal 1, @run.run_messages.count
    assert_empty other.run_messages
  end

  test "context revisions fail closed and external URLs are not fetched" do
    message = Message.create!(room: @room, creator: users(:david), body: "Original")
    resolver = AgentNative::ContextResolver.new(profile: @profile, room: @room)
    selection = { "references" => [ { "kind" => "message", "id" => message.id.to_s, "source_room_id" => @room.id.to_s, "revision" => 999 } ], "include_current_request" => false }
    assert_equal "changed", resolver.resolve(selection)[:items].first[:availability]
    assert_raises(AgentNative::Error) { resolver.require_current!(selection) }
    assert_raises(AgentNative::Error) { AgentNative::ContextResolver.safe_uri!("file:///etc/passwd") }
    assert_raises(AgentNative::Error) { AgentNative::ContextResolver.safe_uri!("https://secret@example.test/x") }
  end
end
