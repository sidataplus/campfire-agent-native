module AgentNativeActionApi
  def list_actions
    scope = AgentNative::Action.where(profile: @profile, room_id: @profile.allowed_rooms.select(:id))
    scope = scope.where.not(room_id: Rooms::Direct.select(:id)) unless @credential.effective_scopes.include?("dms:read")
    render json: page(scope) { |action| action.wire }
  end

  def create_action
    subject = if @input["run_id"]
      AgentNative::Run.visible_to(@profile).find(@input["run_id"])
    else
      AgentNative::Invocation.find_by!(id: @input["invocation_id"], profile: @profile)
    end
    room = room!(subject.room_id, "actions:write")
    mutate do
      AgentNative::ContextResolver.new(profile: @profile, room: room, credential: @credential).require_current!({ "references" => @input.fetch("subject_references"), "include_current_request" => false })
      ref(AgentNative::Action.propose!(@profile, @input), "action")
    end
  end

  def get_action
    action = native_action!
    response.set_header("ETag", etag(action))
    render json: action.wire
  end

  def invalidate_action
    action = native_action!(scope: "actions:write")
    mutate do
      precondition!(action)
      raise AgentNative::Error.new("action_resolved", 409) unless action.state == "pending"
      action.update!(state: "invalidated", version: action.version + 1)
      AgentNative::Event.publish!(kind: "action.invalidated", resource: action, room: action.room, profile: @profile, actor: @profile)
      ref(action, "action")
    end
  end

  def create_runtime_receipt
    subject = @input.fetch("subject")
    model = { "run" => AgentNative::Run, "action" => AgentNative::Action, "invocation" => AgentNative::Invocation }[subject.fetch("type")]
    raise AgentNative::Error.new("unsupported_subject", 422) unless model
    record = model.find(subject.fetch("id"))
    room = room!(record.room_id, "receipts:write")
    mutate do
      AgentNative::ContextResolver.new(profile: @profile, room: room, credential: @credential).require_current!({ "references" => @input.fetch("evidence"), "include_current_request" => false })
      ref(AgentNative::Receipt.record_runtime!(@profile, @input), "receipt")
    end
  end

  def get_receipt
    receipt = AgentNative::Receipt.find_by!(id: params[:receipt_id], profile: @profile)
    room!(receipt.room_id, "receipts:read")
    render json: receipt.wire
  end

  private
    def native_action!(scope: "actions:read")
      action = AgentNative::Action.find_by!(id: params[:action_id], profile: @profile)
      room!(action.room_id, scope)
      action
    end
end
