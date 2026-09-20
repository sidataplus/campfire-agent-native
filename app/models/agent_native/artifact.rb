class AgentNative::Artifact < AgentNative::Record
  belongs_to :room
  belongs_to :run, optional: true
  belongs_to :publisher_profile, class_name: "AgentNative::Profile"
  has_one_attached :file

  def self.publish!(profile, input)
    room = profile.allowed_rooms.find(input.fetch("room_id"))
    if input["run_id"]
      run = AgentNative::Run.visible_to(profile).find(input["run_id"])
      run.authorize!(profile, contribution: "artifact")
      raise AgentNative::Error.new("cross_room_reference", 422) unless run.room_id == room.id
      raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
    end
    attributes = input.except("upload_id").merge("publisher_profile_id" => profile.id)
    if input["kind"] == "external"
      AgentNative::ContextResolver.safe_uri!(input.fetch("external_uri"))
    else
      upload = AgentNative::Upload.find(input.fetch("upload_id"))
      raise AgentNative::Error.new("digest_mismatch", 409) unless upload.sha256 == input.fetch("sha256")
      blob = upload.consume!(by: profile, in_room: room)
    end
    artifact = create!(attributes)
    artifact.file.attach(blob) if blob
    AgentNative::Event.publish!(kind: "artifact.created", resource: artifact, room: room, actor: profile)
    artifact
  end

  def wire
    { id: id, room_id: room_id.to_s, run_id: run_id, publisher_profile_id: publisher_profile_id,
      title: title, kind: kind, sha256: sha256, content_type: file.attached? ? file.content_type : nil,
      byte_size: file.attached? ? file.byte_size : nil, external_uri: external_uri, created_at: created_at.iso8601 }.compact
  end
end
