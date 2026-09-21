module AgentNativeHumanRunApi
  def submit_human_run_input
    input = AgentNative::Contract.validate!("HumanRunInput", JSON.parse(request.raw_post))
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      run = AgentNative::Run.where(room_id: Current.user.rooms.select(:id)).find(params[:run_id])
      profile = AgentNative::Profile.find(input.fetch("profile_id"))
      run.authorize!(profile)
      raise AgentNative::Error.new("forbidden", 403) unless profile.operator?(Current.user, run.room)
      raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
      raise AgentNative::Error.new("unsupported_capability", 409) unless profile.manifest.fetch("capabilities").fetch("supports_followup")
      AgentNative::ContextResolver.new(profile: profile, room: run.room, human: Current.user).require_current!(input.fetch("context"))
      result = human_write(input) do
        message = run.run_messages.create!(author_kind: "human", author_id: Current.user.id.to_s,
          body_text: input.fetch("body_text"), client_message_id: input.fetch("client_message_id"))
        invocation = AgentNative::Invocation.submit!(profile: profile, human: Current.user, room: run.room, input: input, run_id: run.id,
          source: { "kind" => "run_message", "id" => message.id, "revision" => message.revision, "source_room_id" => run.room_id.to_s })
        { "type" => "invocation", "id" => invocation.id }
      end
      render json: result, status: :created
    end
  end
end
