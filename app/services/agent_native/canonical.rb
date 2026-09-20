class AgentNative::Canonical
  def self.normalize(value)
    case value
    when Hash then value.sort.to_h.transform_values { |item| normalize(item) }
    when Array then value.map { |item| normalize(item) }
    else value
    end
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(normalize(value)))
  end
end
