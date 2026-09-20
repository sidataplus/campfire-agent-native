class AgentNative::Credential < AgentNative::Record
  belongs_to :profile
  def self.issue!(profile:, scopes:, expires_at: 90.days.from_now)
    allowed = profile.manifest.fetch("requested_scopes")
    raise AgentNative::Error.new("insufficient_scope", 403) unless scopes.is_a?(Array) && (scopes - allowed).empty?
    raw = "acn_#{SecureRandom.urlsafe_base64(32)}"
    [create!(profile: profile, scopes: scopes.uniq, expires_at: expires_at, token_digest: Digest::SHA256.hexdigest(raw)), raw]
  end

  def usable?
    revoked_at.nil? && (expires_at.nil? || expires_at.future?)
  end

  def self.authenticate(raw)
    return unless raw.is_a?(String) && raw.match?(/\Aacn_[A-Za-z0-9_-]{43}\z/)
    find_by(token_digest: Digest::SHA256.hexdigest(raw))&.then { |c| c if c.usable? }
  end
end
