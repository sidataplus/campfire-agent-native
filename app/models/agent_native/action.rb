class AgentNative::Action < AgentNative::Record
  belongs_to :profile
  belongs_to :room
  belongs_to :run, optional: true
  belongs_to :invocation, optional: true
  belongs_to :decision_receipt, class_name: "AgentNative::Receipt", optional: true
  scope :pending, -> { where(state: "pending").where("expires_at > ?", Time.current) }

  def self.propose!(profile, input)
    AgentNative::ActionInput.validate_schema!(input.fetch("input_schema"))
    raise AgentNative::Error.new("unsupported_action", 422) unless profile.manifest.fetch("action_types").include?(input.fetch("operation"))
    subject = input["run_id"] ? AgentNative::Run.visible_to(profile).find(input["run_id"]) : AgentNative::Invocation.find_by!(id: input["invocation_id"], profile: profile)
    if subject.is_a?(AgentNative::Run)
      subject.authorize!(profile, owner: true)
      raise AgentNative::Error.new("run_terminal", 409) if subject.terminal?
    end
    raise ActiveRecord::RecordNotFound unless profile.allowed_rooms.exists?(subject.room_id)
    reviewers = input.fetch("reviewer_user_ids").uniq
    raise AgentNative::Error.new("invalid_reviewer", 422) unless reviewers.all? { |id| profile.operator?(User.find_by(id: id), subject.room) }
    expiry = Time.iso8601(input.fetch("expires_at"))
    raise AgentNative::Error.new("invalid_expiry", 422) unless expiry > Time.current && expiry <= 7.days.from_now
    AgentNative::ContextResolver.new(profile: profile, room: subject.room).require_current!({ "references" => input.fetch("subject_references"), "include_current_request" => false })
    action = new(input.merge("profile_id" => profile.id, "room_id" => subject.room_id,
      "reviewer_user_ids" => reviewers, "stream_epoch" => AgentNative::Instance.current.stream_epoch,
      "run_version" => subject.is_a?(AgentNative::Run) ? subject.version : nil,
      "owner_generation" => subject.is_a?(AgentNative::Run) ? subject.owner_generation : nil))
    action.proposal_digest = action.compute_digest
    action.save!
    AgentNative::Event.publish!(kind: "action.created", resource: action, room: action.room, profile: profile, actor: profile)
    action
  end

  def compute_digest
    AgentNative::Canonical.digest(attributes.slice("profile_id", "room_id", "run_id", "invocation_id", "kind", "operation", "title", "description",
      "arguments", "input_schema", "subject_references", "reviewer_user_ids", "stream_epoch", "run_version", "owner_generation").merge("expires_at" => expires_at&.iso8601))
  end

  def current_proposal!
    raise AgentNative::Error.new("proposal_changed", 409) unless proposal_digest == compute_digest
    raise AgentNative::Error.new("action_expired", 409) unless expires_at.future?
    raise AgentNative::Error.new("stream_reset", 409) unless stream_epoch == AgentNative::Instance.current.stream_epoch
    if run
      raise AgentNative::Error.new("proposal_changed", 409) if run.terminal? || run.version != run_version || run.owner_generation != owner_generation || run.needs_reconciliation
    end
    AgentNative::ContextResolver.new(profile: profile, room: room).require_current!({ "references" => subject_references, "include_current_request" => false })
  end

  def decide!(human, input)
    raise AgentNative::Error.new("dispatch_disabled", 409) unless AgentNative::Instance.current.dispatch_allowed?
    raise AgentNative::Error.new("forbidden", 403) unless profile.enabled && profile.operator?(human, room) && reviewer_user_ids.include?(human.id.to_s)
    raise AgentNative::Error.new("action_resolved", 409) unless state == "pending"
    current_proposal!
    raise AgentNative::Error.new("proposal_changed", 409) unless input.fetch("proposal_digest") == proposal_digest
    decision = input.fetch("decision")
    allowed = kind == "question" ? %w[ respond reject ] : %w[ approve reject ]
    raise AgentNative::Error.new("validation_failed", 422) unless allowed.include?(decision)
    AgentNative::ActionInput.validate!(input_schema, input.fetch("input")) unless decision == "reject"
    evidence = []
    unless input.fetch("input").empty?
      text = JSON.pretty_generate(input.fetch("input"))
      if run
        message = run.run_messages.create!(author_kind: "human", author_id: human.id.to_s, body_text: text, client_message_id: SecureRandom.uuid)
        evidence << { "kind" => "run_message", "id" => message.id, "revision" => message.revision, "source_room_id" => room_id.to_s }
      else
        message = Message.create!(room: room, creator: human, body: ERB::Util.html_escape(text))
        evidence << { "kind" => "message", "id" => message.id.to_s, "revision" => message.agent_revision, "source_room_id" => room_id.to_s }
      end
    end
    receipt = AgentNative::Receipt.create!(profile: profile, room: room, kind: "human_intent", subject_type: "action", subject_id: id,
      actor_kind: "human", actor_id: human.id.to_s, result: decision, evidence: evidence, payload: input)
    update!(state: "resolved", decision_receipt: receipt, version: version + 1)
    AgentNative::Event.publish!(kind: "action.resolved", resource: self, room: room, profile: profile, actor: human)
    receipt
  end

  def wire
    { id: id, room_id: room_id.to_s, run_id: run_id, invocation_id: invocation_id, kind: kind, operation: operation,
      title: title, description: description, arguments: arguments, input_schema: input_schema, subject_references: subject_references,
      proposal_digest: proposal_digest, state: state == "pending" && expires_at.past? ? "expired" : state,
      reviewer_user_ids: reviewer_user_ids, expires_at: expires_at.iso8601, etag: %Q("#{id}:#{version}"), decision_receipt_id: decision_receipt_id }.compact
  end
end
