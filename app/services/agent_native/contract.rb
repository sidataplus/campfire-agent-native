require "time"
require "uri"

class AgentNative::Contract
  DEFINITIONS = JSON.parse(Rails.root.join("docs/agent-native/contracts/schemas.json").read).fetch("$defs").freeze
  def self.validate!(name, value)
    raise AgentNative::Error.new("validation_failed") unless valid?(DEFINITIONS.fetch(name), value)
    value
  end

  # Deterministic subset covering every keyword in the frozen contract. No remote refs.
  def self.valid?(s, v, depth = 0)
    return false if depth > 32
    return valid?(DEFINITIONS.fetch(s["$ref"].delete_prefix("#/$defs/")), v, depth + 1) if s["$ref"]
    check = ->(sub) { valid?(sub, v, depth + 1) }
    return false if s["allOf"] && !s["allOf"].all?(&check)
    return false if s["anyOf"] && !s["anyOf"].any?(&check)
    return false if s["oneOf"] && s["oneOf"].count(&check) != 1
    return false if s["not"] && check.call(s["not"])
    return false if s["if"] && check.call(s["if"]) && s["then"] && !check.call(s["then"])
    return false if s["enum"] && !s["enum"].include?(v)
    return false if s.key?("const") && s["const"] != v
    type = case v
    when Hash then "object"
    when Array then "array"
    when String then "string"
    when Integer then "integer"
    when Numeric then "number"
    when TrueClass, FalseClass then "boolean"
    when NilClass then "null"
    end
    return false if s["type"] && !Array(s["type"]).include?(type) && !(type == "integer" && s["type"] == "number")
    case v
    when Hash
      return false unless (Array(s["required"]) - v.keys).empty?
      return false if s["maxProperties"] && v.size > s["maxProperties"]
      props = s.fetch("properties", {})
      return false if s["additionalProperties"] == false && (v.keys - props.keys).any?
      return false unless v.all? { |k, x| !props[k] || valid?(props[k], x, depth + 1) }
    when Array
      return false if v.size < s.fetch("minItems", 0) || v.size > s.fetch("maxItems", 1000)
      return false if s["items"] && !v.all? { |x| valid?(s["items"], x, depth + 1) }
    when String
      return false unless v.valid_encoding?
      return false if v.length < s.fetch("minLength", 0) || v.length > s.fetch("maxLength", 262144)
      return false if s["pattern"] && !Regexp.new(s["pattern"].sub(/\A\^/, "\\A").sub(/\$\z/, "\\z")).match?(v)
      return false if s["format"] == "uuid" && !v.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      if s["format"] == "date-time"
        return false unless v.match?(/(?:Z|[+-][0-9]{2}:[0-9]{2})\z/)
        Time.iso8601(v)
      end
      return false if s["format"] == "uri" && !URI.parse(v).absolute?
    when Numeric
      return false if v < s.fetch("minimum", -Float::INFINITY) || v > s.fetch("maximum", Float::INFINITY)
    end
    true
  rescue ArgumentError, URI::InvalidURIError, KeyError, TypeError
    false
  end
end
