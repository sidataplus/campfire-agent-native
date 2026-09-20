class AgentNative::Invocation < AgentNative::Record
  belongs_to :profile
  belongs_to :room
  belongs_to :human_user, class_name: "User"

  def self.submit!(profile:, human:, room:, input:, source:, run_id: nil)
    raise AgentNative::Error.new("dispatch_disabled", 409) unless AgentNative::Instance.current.dispatch_allowed?
    raise AgentNative::Error.new("forbidden", 403) unless profile.enabled && profile.operator?(human, room) && profile.allowed_rooms.exists?(room.id)
    raise AgentNative::Error.new("activation_disabled", 403) if profile.room_grants.find_by!(room: room).activation == "disabled"
    modes = profile.manifest.fetch("capabilities").fetch("modes")
    raise AgentNative::Error.new("unsupported_capability", 409) unless (modes & %w[interactive task]).any?
    AgentNative::Contract.validate!("HumanRunInput", input)
    invocation = create!(profile: profile, human_user: human, room: room, normalized_input: input.fetch("body_text"),
      source: source, context: input.fetch("context"), run_id: run_id,
      source_digest: AgentNative::Canonical.digest([ source, input.fetch("body_text"), input.fetch("context") ]),
      admission_expires_at: 15.minutes.from_now, stream_epoch: AgentNative::Instance.current.stream_epoch)
    AgentNative::Event.publish!(kind: "invocation.created", resource: invocation, room: room, profile: profile, actor: human)
    invocation
  end

  def admit!(input)
    instance = AgentNative::Instance.current
    raise AgentNative::Error.new("dispatch_disabled", 409) unless instance.dispatch_allowed? && stream_epoch == instance.stream_epoch
    raise AgentNative::Error.new("forbidden", 403) unless profile.operator?(human_user, room)
    raise AgentNative::Error.new("invocation_unavailable", 409) unless disposition == "pending" && admission_expires_at.future?
    raise AgentNative::Error.new("source_changed", 409) unless input.fetch("source_digest") == source_digest
    if source["kind"] == "message"
      message = room.messages.find_by(id: source["id"])
      raise AgentNative::Error.new("source_changed", 409) unless message && message.agent_revision == source["revision"] && message.plain_text_body == normalized_input
    end
    update!(disposition: input.fetch("disposition"), runtime_operation_id: input.fetch("runtime_operation_id"), version: version + 1)
    AgentNative::Event.publish!(kind: "invocation.#{disposition}", resource: self, room: room, profile: profile, actor: profile)
  end

  def wire
    { id: id, profile_id: profile_id, room_id: room_id.to_s, human_user_id: human_user_id.to_s,
      source: source, normalized_input: normalized_input, context: context, run_id: run_id,
      created_at: created_at.iso8601, admission_expires_at: admission_expires_at.iso8601,
      disposition: disposition, source_digest: source_digest, etag: %Q("#{id}:#{version}") }.compact
  end
end
