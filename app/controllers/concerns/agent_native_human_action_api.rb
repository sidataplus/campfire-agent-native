module AgentNativeHumanActionApi
  def submit_human_decision
    input = AgentNative::Contract.validate!("HumanDecision", JSON.parse(request.raw_post))
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      action = AgentNative::Action.where(room_id: Current.user.rooms.select(:id)).find(params[:action_id])
      raise AgentNative::Error.new("forbidden", 403) unless AgentNative::Attention.visible_action?(Current.user, action)
      result = human_write(input) do
        raise AgentNative::Error.new("precondition_required", 428) unless request.headers["If-Match"]
        raise AgentNative::Error.new("version_conflict", 412) unless request.headers["If-Match"] == %Q("#{action.id}:#{action.version}")
        receipt = action.decide!(Current.user, input)
        { "type" => "receipt", "id" => receipt.id }
      end
      render json: result, status: :created
    end
  end

  def request_human_control
    input = AgentNative::Contract.validate!("HumanControl", JSON.parse(request.raw_post))
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      run = AgentNative::Run.where(room_id: Current.user.rooms.select(:id)).find(params[:run_id])
      raise AgentNative::Error.new("forbidden", 403) unless run.owner_profile.operator?(Current.user, run.room)
      result = human_write(input) do
        expected_etag = %Q("#{run.id}:#{run.version}")
        raise AgentNative::Error.new("precondition_required", 428) unless request.headers["If-Match"]
        raise AgentNative::Error.new("version_conflict", 412) unless request.headers["If-Match"] == expected_etag
        receipt = AgentNative::Control.request!(run, Current.user, input)
        { "type" => "receipt", "id" => receipt.id }
      end
      render json: result, status: :created
    end
  end

  def get_human_attention
    limit = Integer(params.fetch(:limit, "50").to_s, 10) rescue 0
    after = nil
    if params[:cursor]
      after = Rails.application.message_verifier("agent-attention").verified(params[:cursor], purpose: Current.user.id.to_s)
      raise AgentNative::Error.new("invalid_cursor", 409) unless after
    end
    result = AgentNative::Attention.page(Current.user, after: after, limit: limit)
    cursor = result[:more] ? Rails.application.message_verifier("agent-attention").generate(result[:last_id], purpose: Current.user.id.to_s, expires_in: 15.minutes) : nil
    render json: { items: result[:items], page: { next_cursor: cursor, has_more: result[:more] } }
  end

  def mark_attention_read
    input = AgentNative::Contract.validate!("ReadMarker", JSON.parse(request.raw_post))
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      action = AgentNative::Action.find(params[:item_id])
      raise AgentNative::Error.new("forbidden", 403) unless AgentNative::Attention.visible_action?(Current.user, action)
      result = human_write(input) do
        marker = AgentNative::AttentionRead.find_or_initialize_by(user: Current.user, item_id: action.id)
        marker.update!(read: input.fetch("read"))
        { "ok" => true }
      end
      render json: result.fetch("resource"), status: :created
    end
  end
end
