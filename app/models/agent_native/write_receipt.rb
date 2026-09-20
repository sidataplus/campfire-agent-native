class AgentNative::WriteReceipt < AgentNative::Record
  # Call inside Instance.with_lock, after rechecking current authorization.
  def self.perform!(principal:, key:, fingerprint:)
    raise AgentNative::Error.new("idempotency_key_required", 400) unless key.is_a?(String) && key.bytesize.between?(16, 128)
    digest = Digest::SHA256.hexdigest(key)
    if previous = find_by(principal: principal, key_digest: digest)
      raise AgentNative::Error.new("idempotency_conflict", 409) unless previous.request_digest == fingerprint
      return previous.result.merge("replayed" => true)
    end
    resource = yield
    result = { "resource" => resource, "replayed" => false }
    create!(principal: principal, key_digest: digest, request_digest: fingerprint, result: result)
    result
  end
end
