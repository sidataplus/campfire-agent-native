class AgentNative::Consumer < AgentNative::Record
  belongs_to :profile

  def cursor(sequence = checkpoint)
    Rails.application.message_verifier("agent-event").generate(
      { "consumer" => id, "epoch" => stream_epoch, "authorization" => authorization_version, "sequence" => sequence },
      purpose: profile_id, expires_in: 30.days)
  end

  def sequence!(token)
    instance = AgentNative::Instance.current
    raise AgentNative::Error.new("recovery_required", 409) if instance.recovery_required || instance.recovery_digest != Digest::SHA256.hexdigest(ENV.fetch("CAMPFIRE_RECOVERY_EPOCH", "development"))
    decoded = Rails.application.message_verifier("agent-event").verified(token, purpose: profile_id)
    raise AgentNative::Error.new("invalid_cursor", 409) unless decoded && decoded["consumer"] == id
    raise AgentNative::Error.new("stream_reset", 409) unless decoded["epoch"] == instance.stream_epoch && stream_epoch == instance.stream_epoch
    raise AgentNative::Error.new("access_changed", 409) unless decoded["authorization"] == profile.reload.authorization_version && authorization_version == profile.authorization_version
    sequence = decoded["sequence"]
    raise AgentNative::Error.new("invalid_cursor", 409) unless sequence.is_a?(Integer) && sequence >= enrollment_floor
    raise AgentNative::Error.new("history_expired", 409) if sequence < instance.event_floor
    raise AgentNative::Error.new("history_regressed", 409) if sequence > (AgentNative::Event.maximum(:id) || instance.event_floor)
    sequence
  end

  def wire
    { id: id, profile_id: profile_id, name: name, cursor: cursor,
      authorization_version: authorization_version, stream_epoch: stream_epoch }
  end

  def reset_to_present!
    high = AgentNative::Event.maximum(:id) || AgentNative::Instance.current.event_floor
    update!(enrollment_floor: high, checkpoint: high, delivered: high,
      authorization_version: profile.reload.authorization_version, stream_epoch: AgentNative::Instance.current.stream_epoch)
  end
end
