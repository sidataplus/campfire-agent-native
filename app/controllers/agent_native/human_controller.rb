class AgentNative::HumanController < ApplicationController
  before_action :native_human!
  rescue_from AgentNative::Error, with: :native_problem
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ActionController::ParameterMissing, JSON::ParserError, with: -> { head :unprocessable_entity }

  def create_invocation
    input = AgentNative::Contract.validate!("HumanRunInput", JSON.parse(request.raw_post))
    AgentNative::Instance.current.with_lock do
      AgentNative::Instance.current.touch
      room = Current.user.rooms.find(params[:room_id])
      profile = AgentNative::Profile.find(input.fetch("profile_id"))
      raise AgentNative::Error.new("forbidden", 403) unless profile.operator?(Current.user, room)
      # Until richer context resolution lands, only an empty selection is accepted here.
      raise AgentNative::Error.new("context_unavailable", 422) unless input.fetch("context").fetch("references").empty?
      result = human_write(input) do
        message = Message.create!(room: room, creator: Current.user, body: ERB::Util.html_escape(input.fetch("body_text")), client_message_id: input.fetch("client_message_id"))
        invocation = AgentNative::Invocation.submit!(profile: profile, human: Current.user, room: room, input: input,
          source: { "kind" => "message", "id" => message.id.to_s, "revision" => message.agent_revision, "source_room_id" => room.id.to_s })
        { "type" => "invocation", "id" => invocation.id }
      end
      render json: result, status: :created
    end
  end

  private
    def native_human!
      raise AgentNative::Error.new("not_found", 404) unless AgentNative.enabled?
      raise AgentNative::Error.new("forbidden", 403) unless Current.user&.active? && !Current.user.bot? && request.authorization.blank?
      raise AgentNative::Error.new("payload_too_large", 413) if request.content_length.to_i > 262144
      response.set_header("Cache-Control", "private, no-store")
    end

    def human_write(input)
      AgentNative::WriteReceipt.perform!(principal: "human:#{Current.user.id}", key: request.headers["Idempotency-Key"],
        fingerprint: AgentNative::Canonical.digest([ request.method, request.path, input ])) { yield }
    end

    def native_problem(error)
      render json: { type: "about:blank", title: error.code.humanize, code: error.code,
        status: error.status, request_id: request.request_id }, status: error.status, content_type: "application/problem+json"
    end
end
