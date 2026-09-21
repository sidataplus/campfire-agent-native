class AgentNative::Activity < AgentNative::Record
  belongs_to :run
  belongs_to :profile

  TERMINAL_STATES = %w[ completed failed cancelled ].freeze

  def self.report!(run, profile, input)
    run.authorize!(profile, contribution: "activity")
    raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
    raise AgentNative::Error.new("owner_fenced", 409) unless input.fetch("owner_generation") == run.owner_generation
    activity = find_or_initialize_by(run: run, profile: profile, operation_id: input.fetch("operation_id"))
    if activity.persisted?
      raise AgentNative::Error.new("stale_revision", 409) unless input.fetch("source_revision") > activity.operation.fetch("source_revision")
      if TERMINAL_STATES.include?(activity.operation["state"]) && activity.operation["state"] != input["state"]
        raise AgentNative::Error.new("invalid_transition", 409)
      end
    end
    AgentNative::ContextResolver.new(profile: profile, room: run.room).require_current!({ "references" => input.fetch("evidence"), "include_current_request" => false })
    activity.update!(operation: input)
    AgentNative::Event.publish!(kind: "activity.updated", resource: activity, room: run.room, actor: profile)
    activity
  end

  def wire
    { id: id, run_id: run_id, profile_id: profile_id, operation: operation, updated_at: updated_at.iso8601 }
  end
end
