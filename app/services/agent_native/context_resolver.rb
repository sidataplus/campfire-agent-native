class AgentNative::ContextResolver
  def initialize(profile:, room: nil, human: nil, credential: nil)
    @profile, @room, @human, @credential = profile, room, human, credential
  end

  def self.safe_uri!(text)
    uri = URI.parse(text)
    raise AgentNative::Error.new("unsafe_reference", 422) unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo
    uri.to_s
  rescue URI::InvalidURIError
    raise AgentNative::Error.new("unsafe_reference", 422)
  end

  def resolve(selection)
    AgentNative::Contract.validate!("ContextSelection", selection)
    items = selection.fetch("references").map { |reference| resolve_one(reference) }
    token = Rails.application.message_verifier("agent-context").generate(Digest::SHA256.hexdigest(items.to_json), purpose: @profile.id, expires_in: 30.minutes)
    { items: items, snapshot_cursor: token, has_more: false }
  end

  def require_current!(selection)
    result = resolve(selection)
    raise AgentNative::Error.new("context_changed", 409) unless result[:items].all? { |item| item[:availability] == "available" }
    result
  end

  private
    def resolve_one(reference)
      item = { reference: reference, availability: "unavailable" }
      if reference["kind"] == "external"
        self.class.safe_uri!(reference.fetch("external_uri"))
        return item.merge(availability: "available")
      end
      record, room, revision, body = case reference.fetch("kind")
      when "message"
        record = Message.find(reference.fetch("id"))
        [ record, record.room, record.agent_revision, record.plain_text_body ]
      when "run_message"
        record = AgentNative::RunMessage.find(reference.fetch("id"))
        record.run.authorize!(@profile)
        [ record, record.run.room, record.revision, record.body_text ]
      when "artifact"
        record = AgentNative::Artifact.find(reference.fetch("id"))
        record.run&.authorize!(@profile)
        [ record, record.room, nil, nil ]
      end
      return item if @room && room.id != @room.id
      return item if @human && !@human.rooms.exists?(room.id)
      return item unless @profile.allowed_rooms.exists?(room.id)
      return item if reference["source_room_id"] && reference["source_room_id"] != room.id.to_s
      scope = reference["kind"] == "artifact" ? "attachments:read" : "messages:read"
      @profile.authorize!(@credential, scope, room) if @credential
      grant = @profile.room_grants.find_by!(room: room)
      return item if grant.history_policy == "since_grant" && record.created_at < grant.created_at
      return item.merge(availability: "changed") if reference["revision"] && revision != reference["revision"]
      hash = record.respond_to?(:sha256) ? record.sha256 : Digest::SHA256.hexdigest(body.to_s)
      return item.merge(availability: "changed") if reference["sha256"] && reference["sha256"] != hash
      item.merge(availability: "available", body_text: body, artifact: reference["kind"] == "artifact" ? { type: "artifact", id: record.id } : nil).compact
    rescue ActiveRecord::RecordNotFound, AgentNative::Error
      item
    end
end
