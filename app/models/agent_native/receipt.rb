class AgentNative::Receipt < AgentNative::Record
  belongs_to :profile
  belongs_to :room
  before_update { raise ActiveRecord::ReadOnlyRecord, "Receipts are immutable" }
  before_destroy { throw :abort }

  def self.record_runtime!(profile, input)
    reference = input.fetch("subject")
    subject = case reference.fetch("type")
    when "run" then AgentNative::Run.find_by!(id: reference.fetch("id"), owner_profile: profile)
    when "action" then AgentNative::Action.find_by!(id: reference.fetch("id"), profile: profile)
    when "invocation" then AgentNative::Invocation.find_by!(id: reference.fetch("id"), profile: profile)
    else raise AgentNative::Error.new("unsupported_subject", 422)
    end
    raise ActiveRecord::RecordNotFound unless profile.allowed_rooms.exists?(subject.room_id)
    if input["kind"] == "admission" && input["result"] == "accepted"
      raise AgentNative::Error.new("dispatch_disabled", 409) unless AgentNative::Instance.current.dispatch_allowed?
    end
    if subject.is_a?(AgentNative::Run)
      raise AgentNative::Error.new("owner_fenced", 409) unless input["owner_generation"] == subject.owner_generation
    elsif subject.is_a?(AgentNative::Action)
      decision = subject.decision_receipt
      raise AgentNative::Error.new("decision_required", 409) unless decision && input["decision_receipt_id"] == decision.id
      if input["kind"] == "admission" && input["result"] == "accepted"
        subject.current_proposal!
        human = User.find_by(id: decision.actor_id)
        raise AgentNative::Error.new("forbidden", 403) unless profile.operator?(human, subject.room)
        raise AgentNative::Error.new("decision_rejected", 409) if decision.result == "reject"
        AgentNative::ContextResolver.new(profile: profile, room: subject.room).require_current!({ "references" => decision.evidence, "include_current_request" => false })
      end
    end
    previous = where(profile: profile, runtime_operation_id: input.fetch("runtime_operation_id")).order(source_revision: :desc).first
    if previous
      raise AgentNative::Error.new("operation_conflict", 409) unless previous.subject_type == reference["type"] && previous.subject_id == reference["id"]
      raise AgentNative::Error.new("stale_revision", 409) unless input.fetch("source_revision") > previous.source_revision
      raise AgentNative::Error.new("outcome_terminal", 409) if previous.kind == "outcome" && previous.result != "indeterminate"
    end
    if input["kind"] == "outcome" && subject.is_a?(AgentNative::Action)
      accepted = where(profile: profile, kind: "admission", runtime_operation_id: input.fetch("runtime_operation_id"), subject_id: subject.id, result: "accepted").exists?
      raise AgentNative::Error.new("admission_required", 409) unless accepted
    end
    AgentNative::ContextResolver.new(profile: profile, room: subject.room).require_current!({ "references" => input.fetch("evidence"), "include_current_request" => false })
    receipt = create!(profile: profile, room: subject.room, kind: input.fetch("kind"), subject_type: reference.fetch("type"), subject_id: reference.fetch("id"),
      actor_kind: "agent", actor_id: profile.id, result: input.fetch("result"), evidence: input.fetch("evidence"), payload: input,
      runtime_operation_id: input.fetch("runtime_operation_id"), source_revision: input.fetch("source_revision"), decision_receipt_id: input["decision_receipt_id"])
    AgentNative::Event.publish!(kind: "receipt.created", resource: receipt, room: subject.room, profile: profile, actor: profile)
    receipt
  end

  def wire
    { id: id, kind: kind, subject: { type: subject_type, id: subject_id }, actor_kind: actor_kind, actor_id: actor_id,
      created_at: created_at.iso8601, result: result, runtime_operation_id: runtime_operation_id, evidence: evidence }.compact
  end
end
