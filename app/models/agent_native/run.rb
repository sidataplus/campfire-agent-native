class AgentNative::Run < AgentNative::Record
  belongs_to :room
  belongs_to :owner_profile, class_name: "AgentNative::Profile"
  belongs_to :parent_run, class_name: "AgentNative::Run", optional: true
  has_many :participants, dependent: :destroy
  has_many :run_messages, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :artifacts, dependent: :restrict_with_exception
  TERMINAL = %w[ completed failed cancelled expired ].freeze
  TRANSITIONS = {
    "queued" => %w[ running failed cancelled expired ],
    "running" => %w[ waiting_for_human paused completed failed cancelled expired ],
    "waiting_for_human" => %w[ running paused completed failed cancelled expired ],
    "paused" => %w[ running waiting_for_human failed cancelled expired ]
  }.freeze

  def terminal?
    TERMINAL.include?(state)
  end

  def self.visible_to(profile)
    where(owner_profile_id: profile.id).or(where(id: AgentNative::Participant.where(profile: profile).select(:run_id)))
      .where(room_id: profile.allowed_rooms.select(:id))
  end

  def authorize!(profile, contribution: nil, owner: false)
    raise ActiveRecord::RecordNotFound unless profile.allowed_rooms.exists?(room_id)
    return if owner_profile_id == profile.id
    participant = participants.find_by(profile: profile)
    raise AgentNative::Error.new("forbidden", 403) if owner || !participant || (contribution && !participant.contributions.include?(contribution))
  end

  def fence!(profile, input, mutable: true)
    authorize!(profile, owner: true)
    raise AgentNative::Error.new("owner_fenced", 409) unless input.fetch("owner_generation") == owner_generation
    raise AgentNative::Error.new("reconciliation_required", 409) if needs_reconciliation
    raise AgentNative::Error.new("run_terminal", 409) if mutable && terminal?
  end

  def project!(profile, input)
    fence!(profile, input)
    raise AgentNative::Error.new("stale_revision", 409) unless input.fetch("source_revision") > source_revision
    target = input.fetch("state")
    raise AgentNative::Error.new("invalid_transition", 409) unless target == state || TRANSITIONS.fetch(state, []).include?(target)
    update!(state: target, source_revision: input.fetch("source_revision"), summary: input["summary"], version: version + 1, last_reported_at: Time.current)
    AgentNative::Event.publish!(kind: "run.updated", resource: self, room: room, actor: profile)
  end

  def self.project_new!(profile, input)
    raise AgentNative::Error.new("unsupported_capability", 409) unless profile.manifest.fetch("capabilities").fetch("modes").include?("task")
    room = profile.allowed_rooms.find(input.fetch("room_id"))
    if input["invocation_id"]
      invocation = AgentNative::Invocation.find_by!(id: input["invocation_id"], profile: profile, room: room, disposition: "admitted")
      raise AgentNative::Error.new("source_changed", 409) if invocation.run_id
      raise AgentNative::Error.new("context_changed", 409) unless invocation.context == input.fetch("context")
    end
    %w[ parent_run_id retry_of_run_id continuation_of_run_id ].each do |key|
      next unless input[key]
      linked = visible_to(profile).find(input[key])
      raise AgentNative::Error.new("cross_room_reference", 422) unless linked.room_id == room.id
      if key == "parent_run_id"
        depth = 0
        while linked
          depth += 1
          raise AgentNative::Error.new("ancestry_limit", 422) if depth > 8
          linked = linked.parent_run
        end
      end
    end
    AgentNative::ContextResolver.new(profile: profile, room: room).require_current!(input.fetch("context"))
    if input["initiating_message_id"]
      message = room.messages.find(input["initiating_message_id"])
      raise AgentNative::Error.new("source_changed", 409) if invocation && invocation.source["id"] != message.id.to_s
    end
    run = create!(input.merge("owner_profile_id" => profile.id, "runtime_id" => profile.runtime_id, "last_reported_at" => Time.current))
    AgentNative::Event.publish!(kind: "run.created", resource: run, room: room, actor: profile)
    run
  end

  def wire
    { id: id, room_id: room_id.to_s, owner_profile_id: owner_profile_id, runtime_id: runtime_id,
      external_run_id: external_run_id, title: title, state: state, owner_generation: owner_generation,
      source_revision: source_revision, version: version, etag: %Q("#{id}:#{version}"),
      parent_run_id: parent_run_id, invocation_id: invocation_id, session_ref: session_ref,
      last_reported_at: last_reported_at.iso8601, needs_reconciliation: needs_reconciliation, context: context }.compact
  end
end
