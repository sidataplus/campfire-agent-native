class AgentNative::WorkspaceController < ApplicationController
  before_action :require_native_human
  rescue_from AgentNative::Error, with: :show_error
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from JSON::ParserError, ActionController::ParameterMissing, with: -> { head :unprocessable_entity }

  def index
    @attention = AgentNative::Attention.page(Current.user)[:items]
    @rooms = Current.user.rooms.order(:id).limit(100)
    @runs = AgentNative::Run.where(room_id: Current.user.rooms.select(:id)).order(updated_at: :desc).limit(100)
    @profiles = AgentNative::Profile.where(enabled: true).joins(:operator_grants).where(agent_operator_grants: { user_id: Current.user.id }).distinct
    @recovery = @runs.select(&:needs_reconciliation)
  end

  def show
    @run = visible_run
    @messages = @run.run_messages.order(created_at: :desc).limit(100).to_a.reverse
    @activities = @run.activities.order(updated_at: :desc).limit(100)
    @artifacts = @run.artifacts.order(created_at: :desc).limit(100)
    @actions = AgentNative::Action.pending.where(run: @run).select { |a| AgentNative::Attention.visible_action?(Current.user, a) }
    @receipts = AgentNative::Receipt.where(room: @run.room).where(subject_id: AgentNative::Action.where(run: @run).select(:id)).order(created_at: :desc).limit(50)
    @progress = Rails.cache.read("agent-progress:#{@run.id}:#{@run.owner_generation}") unless @run.terminal?
    @presence = Rails.cache.read("agent-presence:#{@run.owner_profile_id}")
    @can_direct = @run.owner_profile.operator?(Current.user, @run.room)
  end

  def submit
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      profile = AgentNative::Profile.find(params.require(:profile_id))
      run = params[:run_id].present? ? visible_run : nil
      room = run ? run.room : Current.user.rooms.find(params.require(:room_id))
      raise AgentNative::Error.new("forbidden", 403) unless profile.operator?(Current.user, room)
      if run
        run.authorize!(profile)
        raise AgentNative::Error.new("run_terminal", 409) if run.terminal?
        raise AgentNative::Error.new("unsupported_capability", 409) unless profile.manifest.fetch("capabilities").fetch("supports_followup")
      end
      input = { "profile_id" => profile.id, "body_text" => params.require(:body_text).to_s,
        "client_message_id" => params.require(:request_key).to_s,
        "context" => { "references" => [], "include_current_request" => true } }
      AgentNative::Contract.validate!("HumanRunInput", input)
      human_transaction(input) do
        if run
          message = run.run_messages.create!(author_kind: "human", author_id: Current.user.id.to_s, body_text: input["body_text"], client_message_id: input["client_message_id"])
          source = { "kind" => "run_message", "id" => message.id, "revision" => message.revision, "source_room_id" => room.id.to_s }
        else
          message = Message.create!(room: room, creator: Current.user, body: ERB::Util.html_escape(input["body_text"]), client_message_id: input["client_message_id"])
          source = { "kind" => "message", "id" => message.id.to_s, "revision" => message.agent_revision, "source_room_id" => room.id.to_s }
        end
        invocation = AgentNative::Invocation.submit!(profile: profile, human: Current.user, room: room, input: input, source: source, run_id: run&.id)
        { "type" => "invocation", "id" => invocation.id }
      end
      redirect_to run ? "/agent/workspace/runs/#{run.id}" : "/agent/workspace", status: :see_other, notice: "Request recorded. Runtime admission is pending."
    end
  end

  def decide
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      action = AgentNative::Action.find(params.require(:action_id))
      raise AgentNative::Error.new("forbidden", 403) unless AgentNative::Attention.visible_action?(Current.user, action)
      values = typed_fields(action.input_schema, params.fetch(:fields, {}).to_unsafe_h)
      input = { "proposal_digest" => params.require(:proposal_digest).to_s, "decision" => params.require(:decision).to_s, "input" => values }
      AgentNative::Contract.validate!("HumanDecision", input)
      human_transaction(input) do
        raise AgentNative::Error.new("version_conflict", 409) unless params[:version].to_s == action.version.to_s
        receipt = action.decide!(Current.user, input)
        { "type" => "receipt", "id" => receipt.id }
      end
      redirect_to action.run_id ? "/agent/workspace/runs/#{action.run_id}" : "/agent/workspace", status: :see_other, notice: "Decision recorded. This is not confirmation of execution."
    end
  end

  def control
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      run = visible_run
      raise AgentNative::Error.new("forbidden", 403) unless run.owner_profile.operator?(Current.user, run.room)
      input = { "control" => params.require(:control).to_s, "expected_run_version" => Integer(params.require(:version).to_s, 10) }
      AgentNative::Contract.validate!("HumanControl", input)
      human_transaction(input) do
        receipt = AgentNative::Control.request!(run, Current.user, input)
        { "type" => "receipt", "id" => receipt.id }
      end
      redirect_to "/agent/workspace/runs/#{run.id}", status: :see_other, notice: "Control request recorded; execution state awaits runtime acknowledgement."
    end
  end

  def mark_read
    action = AgentNative::Action.find(params.require(:action_id))
    raise AgentNative::Error.new("forbidden", 403) unless AgentNative::Attention.visible_action?(Current.user, action)
    AgentNative::AttentionRead.find_or_initialize_by(user: Current.user, item_id: action.id).update!(read: true)
    redirect_to "/agent/workspace", status: :see_other
  end

  def download
    if params[:artifact_id]
      artifact = AgentNative::Artifact.where(room_id: Current.user.rooms.select(:id)).find(params[:artifact_id])
      raise ActiveRecord::RecordNotFound unless artifact.file.attached?
      blob = artifact.file.blob
    else
      message = Message.where(room_id: Current.user.rooms.select(:id)).find(params[:message_id])
      raise ActiveRecord::RecordNotFound unless message.creator.native_agent? && message.attachment.attached?
      blob = message.attachment.blob
    end
    raise AgentNative::Error.new("payload_too_large", 413) if blob.byte_size > 26214400
    send_data blob.download, filename: blob.filename.to_s, type: "application/octet-stream", disposition: "attachment"
  end

  private
    def require_native_human
      raise AgentNative::Error.new("not_found", 404) unless AgentNative.enabled?
      raise AgentNative::Error.new("forbidden", 403) unless Current.user&.active? && !Current.user.bot? && request.authorization.blank?
      raise AgentNative::Error.new("payload_too_large", 413) if request.content_length.to_i > 262144
      response.set_header("Cache-Control", "private, no-store")
      response.set_header("X-Content-Type-Options", "nosniff")
      response.set_header("Referrer-Policy", "no-referrer")
    end

    def visible_run
      AgentNative::Run.where(room_id: Current.user.rooms.select(:id)).find(params[:run_id])
    end

    def human_transaction(input)
      AgentNative::WriteReceipt.perform!(principal: "human:#{Current.user.id}", key: params.require(:request_key).to_s,
        fingerprint: AgentNative::Canonical.digest([ request.method, request.path, input ])) { yield }
    end

    def typed_fields(schema, raw)
      fields = schema.fetch("properties", {})
      raise AgentNative::Error.new("validation_failed", 422) unless (raw.keys - fields.keys).empty?
      raw.transform_values.with_index { |value, _| value }.each_with_object({}) do |(key, value), result|
        result[key] = case fields.fetch(key).fetch("type")
        when "integer" then Integer(value.to_s, 10)
        when "number" then Float(value.to_s)
        when "boolean" then value == "true"
        else value.to_s
        end
      end
    rescue ArgumentError, TypeError
      raise AgentNative::Error.new("validation_failed", 422)
    end

    def show_error(error)
      render plain: "#{error.code.humanize}. No operation was authorized. Return to the workspace and review the current state.", status: error.status
    end
end
