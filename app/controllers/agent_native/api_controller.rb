class AgentNative::ApiController < ActionController::API
  CATALOG = JSON.parse(Rails.root.join("docs/agent-native/contracts/openapi-catalog.json").read).fetch("operations").index_by { |o| o.fetch("operation_id").underscore }.freeze
  around_action :authorized_request
  rescue_from AgentNative::Error, with: :problem
  rescue_from ActiveRecord::RecordNotFound, with: -> { problem(AgentNative::Error.new("not_found", 404)) }
  rescue_from ActiveRecord::RecordInvalid, ActionController::ParameterMissing, JSON::ParserError,
    with: -> { problem(AgentNative::Error.new("validation_failed", 422)) }
  rescue_from ActiveRecord::RecordNotUnique, with: -> { problem(AgentNative::Error.new("conflict", 409)) }
  rescue_from ActiveRecord::StatementInvalid, with: :database_problem

  def get_instance
    instance = AgentNative::Instance.current
    render json: { instance_id: instance.instance_uuid, stream_epoch: instance.stream_epoch, protocol_version: "1",
      contract_version: "0.1.0", build_revision: ENV.fetch("RAILWAY_GIT_COMMIT_SHA", "unreleased"),
      native_dispatch_enabled: instance.dispatch_allowed?, recovery_required: instance.recovery_required,
      limits: { page_items: 100, json_bytes: 262144, upload_bytes: 26214400, context_messages: 100 } }
  end

  def get_self
    render json: { id: @profile.id, user_id: @profile.user_id.to_s, runtime_id: @profile.runtime_id,
      name: @profile.user.name, enabled: @profile.enabled, capabilities: @profile.manifest.fetch("capabilities"),
      effective_scopes: @credential.effective_scopes, authorization_version: @profile.authorization_version }
  end

  def put_presence
    ttl = @input.fetch("ttl_seconds")
    Rails.cache.write("agent-presence:#{@profile.id}", @input, expires_in: ttl)
    render json: { observed_at: Time.current.iso8601, expires_at: ttl.seconds.from_now.iso8601 }
  end

  def list_rooms
    render json: page(@profile.allowed_rooms.where.not(type: @credential.effective_scopes.include?("dms:read") ? [] : [ "Rooms::Direct" ])) { |room|
      grant = @profile.room_grants.find_by!(room: room)
      { id: room.id.to_s, name: room.name.to_s, kind: room.direct? ? "direct" : (room.open? ? "open" : "closed"),
        history_policy: grant.history_policy, grant_start_at: grant.created_at.iso8601, activation: grant.activation }
    }
  end

  def list_messages
    room = room!(params[:room_id], "messages:read")
    render json: page(history(room)) { |message| message_json(message) }
  end

  def get_message
    message = message!(params[:message_id], "messages:read")
    response.set_header("ETag", etag(message))
    render json: message_json(message)
  end

  def create_message
    room = room!(params[:room_id], "messages:write")
    if @input["reply_to_message_id"]
      target = message!(@input["reply_to_message_id"], "messages:read")
      raise ActiveRecord::RecordNotFound unless target.room_id == room.id
    end
    mutate do
      attrs = { creator: @profile.user, room: room, client_message_id: @input.fetch("client_message_id"),
        body: ERB::Util.html_escape(@input.fetch("body_text", "")) }
      if @input["upload_id"]
        @profile.authorize!(@credential, "attachments:write", room)
        attrs[:attachment] = AgentNative::Upload.find(@input["upload_id"]).consume!(by: @profile, in_room: room)
      end
      ref(Message.create!(attrs), "message")
    end
  end

  def edit_own_message
    message = message!(params[:message_id], "messages:edit_own", own: true)
    mutate do
      precondition!(message)
      raise AgentNative::Error.new("version_conflict", 409) unless @input["expected_revision"] == message.agent_revision
      message.update!(body: ERB::Util.html_escape(@input.fetch("body_text")))
      ref(message, "message")
    end
  end

  def delete_own_message
    id = params[:message_id].to_s
    raise AgentNative::Error.new("validation_failed", 422) unless id.match?(/\A[0-9]{1,24}\z/)
    if Message.exists?(id: id)
      message = message!(id, "messages:edit_own", own: true)
      mutate do
        precondition!(message)
        resource = ref(message, "message")
        AgentNative::MessageTombstone.create!(id: message.id.to_s, profile: @profile, room: message.room, revision: message.agent_revision)
        message.destroy!
        resource
      end
    else
      tombstone = AgentNative::MessageTombstone.find_by!(id: id, profile: @profile)
      room!(tombstone.room_id, "messages:edit_own")
      mutate { raise ActiveRecord::RecordNotFound }
    end
  end

  def get_room_context
    room = room!(params[:room_id], "messages:read")
    scope = history(room)
    if params[:before].present?
      before = params[:before].to_s
      raise AgentNative::Error.new("validation_failed") unless before.match?(/\A[0-9]{1,24}\z/)
      boundary = scope.find_by(id: before)
      raise ActiveRecord::RecordNotFound unless boundary
      scope = scope.where("messages.id < ?", boundary.id)
    end
    direction = params[:before].present? ? :desc : :asc
    result = page(scope, direction: direction) { |m| { reference: { kind: "message", id: m.id.to_s, revision: m.agent_revision, source_room_id: room.id.to_s }, availability: "available", body_text: m.plain_text_body } }
    render json: { items: result[:items], snapshot_cursor: result[:page][:next_cursor] || Rails.application.message_verifier("agent-context").generate(Time.current.iso8601, purpose: @profile.id, expires_in: 30.minutes), has_more: result[:page][:has_more] }
  end

  def search_messages
    room = room!(params.require(:room_id), "search:read")
    q = params.require(:query).to_s
    raise AgentNative::Error.new("validation_failed") unless q.length.between?(1, 1000)
    scope = history(room).joins(:rich_text_body).where("action_text_rich_texts.body LIKE ?", "%#{Message.sanitize_sql_like(q)}%")
    render json: page(scope) { |m| message_json(m) }
  end

  def upload_file
    room = room!(params.require(:room_id), "attachments:write")
    file = params.require(:file)
    raise AgentNative::Error.new("validation_failed") unless file.respond_to?(:tempfile) && file.size.between?(1, 26214400)
    filename = params.require(:filename).to_s
    raise AgentNative::Error.new("validation_failed") unless filename.length.between?(1, 256) && File.basename(filename) == filename && !filename.match?(/[\x00-\x1f\x7f\\]/)
    digest = Digest::SHA256.file(file.tempfile.path).hexdigest
    result = write_result(extra: [ digest, room.id, filename, params[:content_type] ]) do
      upload = AgentNative::Upload.create!(profile: @profile, room: room, sha256: digest, expires_at: 1.hour.from_now)
      upload.file.attach(io: file.tempfile, filename: filename, content_type: "application/octet-stream", identify: false)
      ref(upload, "upload")
    end
    upload = AgentNative::Upload.find(result.fetch("resource").fetch("id"))
    render json: { id: upload.id, room_id: room.id.to_s, filename: upload.file.filename.to_s,
      content_type: upload.file.content_type, byte_size: upload.file.byte_size, sha256: upload.sha256, expires_at: upload.expires_at.iso8601 }, status: :created
  end

  def download_message_attachment
    message = message!(params[:message_id], "attachments:read")
    attachments = message.attachment_attachment ? [ message.attachment_attachment ] : []
    attachments += message.rich_text_body&.embeds_attachments&.to_a || []
    attachment = attachments.find { |a| a.id.to_s == params[:attachment_id] }
    raise ActiveRecord::RecordNotFound unless attachment
    send_blob(attachment.blob)
  end

  private
    def authorized_request
      response.set_header("Cache-Control", "no-store")
      response.set_header("X-Content-Type-Options", "nosniff")
      raise AgentNative::Error.new("not_found", 404) unless AgentNative.enabled?
      raise AgentNative::Error.new("length_required", 411) if action_name == "upload_file" && request.content_length.nil?
      limit = action_name == "upload_file" ? 26300000 : 262144
      raise AgentNative::Error.new("payload_too_large", 413) if request.content_length.to_i > limit
      match = request.authorization.to_s.match(/\ABearer (acn_[A-Za-z0-9_-]{43})\z/)
      @credential = AgentNative::Credential.authenticate(match && match[1])
      raise AgentNative::Error.new("invalid_token", 401) unless @credential
      @profile = @credential.profile
      @operation = CATALOG.fetch(action_name)
      AgentNative::Instance.current.with_lock do
        AgentNative::Instance.current.touch
        @profile.authorize!(@credential)
        @operation.fetch("scopes").each { |s| @profile.authorize!(@credential, s) }
        @credential.update_columns(last_used_at: Time.current) if !@credential.last_used_at || @credential.last_used_at < 5.minutes.ago
        @input = {}
        if schema = @operation.dig("request_body", "content", "application/json", "schema", "$ref")
          raise AgentNative::Error.new("unsupported_media_type", 415) unless request.media_type == "application/json"
          raw = request.body.read(262145)
          raise AgentNative::Error.new("payload_too_large", 413) if raw.bytesize > 262144
          @input = AgentNative::Contract.validate!(schema.split("/").last, JSON.parse(raw))
        end
        yield
      end
    end

    def room!(id, scope)
      raise AgentNative::Error.new("validation_failed", 422) unless id.to_s.match?(/\A[0-9]{1,24}\z/)
      room = @profile.allowed_rooms.find(id)
      @profile.authorize!(@credential, scope, room)
      room
    end

    def history(room)
      grant = @profile.room_grants.find_by!(room: room)
      messages = room.messages
      grant.history_policy == "all_authorized" ? messages : messages.where(created_at: grant.created_at..)
    end

    def message!(id, scope, own: false)
      raise AgentNative::Error.new("validation_failed", 422) unless id.to_s.match?(/\A[0-9]{1,24}\z/)
      message = Message.find(id)
      room = room!(message.room_id, scope)
      raise ActiveRecord::RecordNotFound unless (own && message.creator_id == @profile.user_id) || history(room).exists?(message.id)
      raise AgentNative::Error.new("forbidden", 403) if own && message.creator_id != @profile.user_id
      message
    end

    def message_json(message)
      attachments = if @credential.effective_scopes.include?("attachments:read")
        records = []
        records << message.attachment_attachment if message.attachment.attached?
        records.concat(message.rich_text_body&.embeds_attachments&.to_a || [])
        records.compact.uniq(&:id).first(16).map { |attachment| { type: "upload", id: attachment.id.to_s } }
      else
        []
      end
      { id: message.id.to_s, room_id: message.room_id.to_s, creator_user_id: message.creator_id.to_s,
        creator_kind: message.creator.native_agent? ? "agent" : (message.creator.bot? ? "legacy_bot" : "human"),
        revision: message.agent_revision, body_text: message.plain_text_body,
        created_at: message.created_at.iso8601, updated_at: message.updated_at.iso8601, attachments: attachments, etag: etag(message) }
    end

    def etag(record)
      version = record.respond_to?(:agent_revision) ? record.agent_revision : record.version
      %Q("#{record.id}:#{version}")
    end

    def precondition!(record)
      raise AgentNative::Error.new("precondition_required", 428) unless request.headers["If-Match"]
      raise AgentNative::Error.new("version_conflict", 412) unless request.headers["If-Match"] == etag(record)
    end

    def page(scope, direction: :asc)
      size = Integer(params.fetch(:limit, 50).to_s, 10) rescue 0
      raise AgentNative::Error.new("validation_failed") unless size.between?(1, 100)
      if params[:cursor].present?
        cursor = Rails.application.message_verifier("agent-page").verified(params[:cursor], purpose: page_purpose)
        raise AgentNative::Error.new("invalid_cursor", 409) unless cursor
        comparison = direction == :desc ? "<" : ">"
        scope = scope.where("#{scope.klass.table_name}.id #{comparison} ?", cursor)
      end
      rows = scope.reorder(direction == :desc ? { id: :desc } : :id).limit(size + 1).to_a
      more = rows.size > size
      items = direction == :desc ? rows.take(size).reverse : rows.take(size)
      cursor_id = direction == :desc ? items.first&.id : items.last&.id
      cursor = more ? Rails.application.message_verifier("agent-page").generate(cursor_id, purpose: page_purpose, expires_in: 30.minutes) : nil
      { items: items.map { |r| yield(r) }, page: { next_cursor: cursor, has_more: more } }
    end

    def page_purpose
      Digest::SHA256.hexdigest([ @profile.id, @profile.authorization_version, request.path, params.except(:cursor, :controller, :action).to_unsafe_h.sort ].to_json)
    end

    def write_result(extra: nil)
      fingerprint = AgentNative::Canonical.digest([ request.method, request.path, @input, extra, request.headers["If-Match"] ])
      AgentNative::WriteReceipt.perform!(principal: @profile.id, key: request.headers["Idempotency-Key"], fingerprint: fingerprint) { yield }
    end

    def mutate
      render json: write_result { yield }, status: @operation.fetch("success").keys.first.to_i
    end

    def ref(record, type)
      { "type" => type, "id" => record.id.to_s }
    end

    def send_blob(blob)
      raise AgentNative::Error.new("payload_too_large", 413) if blob.byte_size > 26214400
      send_data blob.download, filename: blob.filename.to_s, type: "application/octet-stream", disposition: "attachment"
    end

    def database_problem(error)
      raise error unless error.cause.is_a?(SQLite3::BusyException) || error.cause.is_a?(SQLite3::LockedException)
      response.set_header("Retry-After", "1")
      problem(AgentNative::Error.new("temporarily_unavailable", 503))
    end

    def problem(error)
      render json: { type: "about:blank", title: error.code.humanize, code: error.code.to_s.upcase,
        status: error.status, request_id: request.request_id }, status: error.status, content_type: "application/problem+json"
    end
end
