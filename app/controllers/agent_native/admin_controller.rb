class AgentNative::AdminController < ApplicationController
  before_action :administrator!
  rescue_from AgentNative::Error, JSON::ParserError, ActiveRecord::RecordInvalid, with: -> { render plain: "Configuration was rejected; review the submitted values.", status: :unprocessable_entity }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  def index
    @profiles = AgentNative::Profile.includes(:user, :room_grants, :operator_grants, :credentials).order(:created_at)
    @rooms = Room.order(:id).limit(200)
    @humans = User.active.where(native_agent: false).where.not(role: :bot).ordered
  end

  def create
    manifest = JSON.parse(params.require(:manifest).to_s)
    AgentNative::Administration.change!(Current.user) do
      AgentNative::Profile.provision!(name: manifest.fetch("name"), manifest: manifest)
    end
    redirect_to "/agent/admin", status: :see_other
  end

  def change
    AgentNative::Administration.change!(Current.user) do
      @profile = AgentNative::Profile.find(params[:profile_id])
      case params.require(:operation)
      when "grant_room"
        room = Room.find(params.require(:room_id))
        @profile.room_grants.find_or_create_by!(room: room) { |g| g.history_policy = "since_grant" }
      when "revoke_room"
        @profile.room_grants.find(params.require(:grant_id)).destroy!
      when "grant_operator"
        @profile.operator_grants.find_or_create_by!(user: User.find(params.require(:user_id)))
      when "revoke_operator"
        @profile.operator_grants.find(params.require(:grant_id)).destroy!
      when "issue_token"
        scopes = Array(params[:scopes])
        _, @token = AgentNative::Credential.issue!(profile: @profile, scopes: scopes)
      when "revoke_token"
        @profile.credentials.find(params.require(:credential_id)).update!(revoked_at: Time.current)
      when "disable"
        @profile.update!(enabled: false, authorization_version: @profile.authorization_version + 1)
        @profile.credentials.update_all(revoked_at: Time.current)
        @profile.user.close_remote_connections if @profile.user.respond_to?(:close_remote_connections)
      else
        raise AgentNative::Error.new("unknown_operation", 422)
      end
    end
    @token ? render(:token) : redirect_to("/agent/admin", status: :see_other)
  end

  private
    def administrator!
      head :not_found and return unless AgentNative.enabled?
      head :forbidden and return unless Current.user&.active? && Current.user.administrator? && !Current.user.bot? && request.authorization.blank?
      head :payload_too_large and return if request.content_length.to_i > 262144
      response.set_header("Cache-Control", "private, no-store")
      response.set_header("Referrer-Policy", "no-referrer")
    end
end
