class AgentNative::Control
  def self.request!(run, human, input)
    profile = run.owner_profile
    raise AgentNative::Error.new("dispatch_disabled", 409) unless AgentNative::Instance.current.dispatch_allowed?
    raise AgentNative::Error.new("forbidden", 403) unless profile.enabled && profile.operator?(human, run.room) && profile.allowed_rooms.exists?(run.room_id)
    raise AgentNative::Error.new("version_conflict", 409) unless input.fetch("expected_run_version") == run.version
    raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
    raise AgentNative::Error.new("reconciliation_required", 409) if run.needs_reconciliation
    control = input.fetch("control")
    unless profile.manifest.fetch("capabilities").fetch("supports_#{control}", false)
      raise AgentNative::Error.new("unsupported_capability", 409)
    end
    action = AgentNative::Action.new(profile: profile, room: run.room, run: run, kind: "control", operation: "control.#{control}",
      title: "#{control.capitalize} requested", description: input.fetch("reason", "Human requested #{control}"), arguments: input,
      input_schema: {}, subject_references: [], reviewer_user_ids: [ human.id.to_s ],
      stream_epoch: AgentNative::Instance.current.stream_epoch, run_version: run.version, owner_generation: run.owner_generation,
      expires_at: 15.minutes.from_now, state: "resolved")
    action.proposal_digest = action.compute_digest
    action.save!
    receipt = AgentNative::Receipt.create!(profile: profile, room: run.room, kind: "human_intent", subject_type: "action", subject_id: action.id,
      actor_kind: "human", actor_id: human.id.to_s, result: "#{control}_requested", evidence: [], payload: input)
    action.update!(decision_receipt: receipt)
    AgentNative::Event.publish!(kind: "action.resolved", resource: action, room: run.room, profile: profile, actor: human)
    receipt
  end
end
