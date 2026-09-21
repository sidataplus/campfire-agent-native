module AgentNativeEventApi
  def create_consumer
    raise AgentNative::Error.new("forbidden", 403) unless (@input.fetch("room_ids") - @profile.allowed_rooms.ids.map(&:to_s)).empty?
    result = write_result do
      consumer = AgentNative::Consumer.create!(profile: @profile, name: @input.fetch("name"),
        room_ids: @input.fetch("room_ids"), event_types: @input.fetch("event_types"),
        authorization_version: @profile.authorization_version, stream_epoch: AgentNative::Instance.current.stream_epoch)
      consumer.reset_to_present!
      ref(consumer, "consumer")
    end
    render json: AgentNative::Consumer.find(result.fetch("resource").fetch("id")).wire, status: :created
  end

  def get_consumer
    render json: consumer!.wire
  end

  def get_events
    consumer = consumer!(params.require(:consumer_id))
    sequence = consumer.sequence!(params.require(:cursor))
    limit = Integer(params.fetch(:limit, "100").to_s, 10) rescue 0
    raise AgentNative::Error.new("validation_failed") unless limit.between?(1, 100)
    scanned = AgentNative::Event.where("id > ?", sequence).order(:id).limit(limit).to_a
    next_sequence = scanned.last&.id || sequence
    scopes = @credential.effective_scopes
    events = scanned.select do |event|
      grant = @profile.room_grants.find_by(room_id: event.room_id)
      next false unless grant && @profile.allowed_rooms.exists?(event.room_id)
      # Enrollment floors and authority versions, not timestamp precision, bound replay.
      next false if consumer.room_ids.any? && !consumer.room_ids.include?(event.room_id.to_s)
      next false if event.profile_id && event.profile_id != @profile.id
      next false unless event.visible_to_profile?(@profile)
      next false if consumer.event_types.any? && !consumer.event_types.include?(event.kind)
      next false if event.kind.start_with?("message.") && !scopes.include?("messages:read")
      next false if event.kind.start_with?("invocation.") && !scopes.include?("invocations:read")
      required_scope = {
        "room" => "rooms:read", "run" => "runs:read", "run_message" => "runs:read",
        "activity" => "runs:read", "artifact" => "attachments:read", "action" => "actions:read", "receipt" => "receipts:read"
      }[event.resource_type]
      next false if required_scope && !scopes.include?(required_scope)
      next false if event.room.direct? && !scopes.include?("dms:read")
      true
    end
    consumer.update!(delivered: [ consumer.delivered, next_sequence ].max)
    render json: { events: events.map(&:wire), next_cursor: consumer.cursor(next_sequence),
      has_more: AgentNative::Event.where("id > ?", next_sequence).exists?,
      stream_epoch: consumer.stream_epoch, authorization_version: consumer.authorization_version }
  end

  def ack_consumer
    consumer = consumer!
    mutate do
      sequence = consumer.sequence!(@input.fetch("cursor"))
      raise AgentNative::Error.new("invalid_cursor", 409) unless sequence.between?(consumer.checkpoint, consumer.delivered)
      consumer.update!(checkpoint: sequence)
      ref(consumer, "consumer")
    end
  end

  def resync_consumer
    consumer = consumer!
    write_result { consumer.reset_to_present!; ref(consumer, "consumer") }
    render json: { consumer: consumer.reload.wire, snapshot_token: consumer.cursor, dispatch_allowed: false, reconciliation_required: true }, status: :created
  end

  def list_invocations
    scope = AgentNative::Invocation.where(profile: @profile, room_id: @profile.allowed_rooms.select(:id))
    scope = scope.where.not(room_id: Rooms::Direct.select(:id)) unless @credential.effective_scopes.include?("dms:read")
    render json: page(scope) { |i| i.wire }
  end

  def get_invocation
    invocation = invocation!
    response.set_header("ETag", etag(invocation))
    render json: invocation.wire
  end

  def admit_invocation
    invocation = invocation!
    mutate { precondition!(invocation); invocation.admit!(@input); ref(invocation, "invocation") }
  end

  private
    def consumer!(id = params[:consumer_id])
      AgentNative::Consumer.find_by!(id: id, profile: @profile)
    end

    def invocation!(id = params[:invocation_id])
      invocation = AgentNative::Invocation.find_by!(id: id, profile: @profile)
      room!(invocation.room_id, action_name == "admit_invocation" ? "invocations:admit" : "invocations:read")
      invocation
    end
end
