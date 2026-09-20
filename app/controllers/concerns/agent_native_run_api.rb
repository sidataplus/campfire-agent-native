module AgentNativeRunApi
  def resolve_context
    render json: AgentNative::ContextResolver.new(profile: @profile, credential: @credential).resolve(@input)
  end

  def list_runs
    scope = AgentNative::Run.visible_to(@profile)
    scope = scope.where(room: room!(params[:room_id], "runs:read")) if params[:room_id]
    scope = scope.where.not(room_id: Rooms::Direct.select(:id)) unless @credential.scopes.include?("dms:read")
    render json: page(scope) { |run| run.wire }
  end

  def create_run
    room = room!(@input.fetch("room_id"), "runs:write")
    mutate do
      AgentNative::ContextResolver.new(profile: @profile, room: room, credential: @credential).require_current!(@input.fetch("context"))
      ref(AgentNative::Run.project_new!(@profile, @input), "run")
    end
  end

  def get_run
    run = run!
    response.set_header("ETag", etag(run))
    render json: run.wire
  end

  def update_run
    run = run!(owner: true)
    mutate { precondition!(run); run.project!(@profile, @input); ref(run, "run") }
  end

  def add_run_participant
    run = run!(owner: true)
    mutate do
      precondition!(run)
      raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
      profile = AgentNative::Profile.find(@input.fetch("profile_id"))
      run.participants.create!(profile: profile, contributions: @input.fetch("contributions"))
      run.increment!(:version)
      AgentNative::Event.publish!(kind: "run.participant.changed", resource: run, room: run.room, actor: @profile)
      ref(run, "run")
    end
  end

  def remove_run_participant
    run = run!(owner: true)
    mutate do
      precondition!(run)
      run.participants.find_by!(profile_id: params[:profile_id]).destroy!
      run.increment!(:version)
      AgentNative::Event.publish!(kind: "run.participant.changed", resource: run, room: run.room, actor: @profile)
      ref(run, "run")
    end
  end

  def list_run_messages
    render json: page(run!.run_messages) { |message| message.wire }
  end

  def create_run_message
    run = run!(contribution: "message")
    mutate do
      raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
      ref(run.run_messages.create!(@input.merge("author_kind" => "agent", "author_id" => @profile.id)), "run_message")
    end
  end

  def get_run_context
    run = run!
    render json: AgentNative::ContextResolver.new(profile: @profile, room: run.room, credential: @credential).resolve(run.context)
  end

  def list_activity
    render json: page(run!.activities) { |activity| activity.wire }
  end

  def put_activity
    run = run!(contribution: "activity")
    raise AgentNative::Error.new("validation_failed") unless params[:operation_id] == @input.fetch("operation_id")
    mutate do
      AgentNative::ContextResolver.new(profile: @profile, room: run.room, credential: @credential).require_current!({ "references" => @input.fetch("evidence"), "include_current_request" => false })
      ref(AgentNative::Activity.report!(run, @profile, @input), "activity")
    end
  end

  def put_progress
    run = run!(owner: true)
    run.fence!(@profile, @input)
    raise AgentNative::Error.new("validation_failed") if @input["current"] && @input["total"] && @input["current"] > @input["total"]
    key = "agent-progress:#{run.id}:#{run.owner_generation}"
    previous = Rails.cache.read(key)
    raise AgentNative::Error.new("stale_revision", 409) if previous && previous.fetch("source_revision") >= @input.fetch("source_revision")
    Rails.cache.write(key, @input, expires_in: 30.seconds)
    render json: { expires_at: 30.seconds.from_now.iso8601, accepted: true }
  end

  def create_artifact
    room!(@input.fetch("room_id"), "attachments:write")
    raise AgentNative::Error.new("unsupported_capability", 409) unless @profile.manifest.fetch("capabilities").fetch("supports_artifacts")
    mutate { ref(AgentNative::Artifact.publish!(@profile, @input), "artifact") }
  end

  def list_run_artifacts
    render json: page(run!.artifacts) { |artifact| artifact.wire }
  end

  def get_artifact
    render json: artifact!.wire
  end

  def download_artifact
    artifact = artifact!
    raise ActiveRecord::RecordNotFound unless artifact.file.attached?
    send_blob(artifact.file.blob)
  end

  private
    def run!(owner: false, contribution: nil)
      run = AgentNative::Run.visible_to(@profile).find(params[:run_id])
      @operation.fetch("scopes").each { |scope| room!(run.room_id, scope) }
      run.authorize!(@profile, owner: owner, contribution: contribution)
      run
    end

    def artifact!
      artifact = AgentNative::Artifact.find(params[:artifact_id])
      room!(artifact.room_id, "attachments:read")
      artifact.run&.authorize!(@profile)
      artifact
    end
end
