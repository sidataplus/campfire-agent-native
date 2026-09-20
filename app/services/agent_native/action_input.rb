class AgentNative::ActionInput
  ROOT_KEYS = %w[ type properties required additionalProperties ].freeze
  FIELD_KEYS = %w[ type title description enum minLength maxLength minimum maximum ].freeze

  def self.validate_schema!(schema)
    raise AgentNative::Error.new("unsupported_input_schema", 422) unless schema.is_a?(Hash) && (schema.keys - ROOT_KEYS).empty?
    return if schema.empty?
    properties = schema.fetch("properties", {})
    unless schema["type"] == "object" && properties.is_a?(Hash) && properties.size <= 32 && schema.fetch("additionalProperties", false) == false &&
        schema.fetch("required", []).is_a?(Array) && (schema.fetch("required", []) - properties.keys).empty?
      raise AgentNative::Error.new("unsupported_input_schema", 422)
    end
    properties.each do |name, field|
      unless name.match?(/\A[A-Za-z][A-Za-z0-9_]{0,63}\z/) && field.is_a?(Hash) && (field.keys - FIELD_KEYS).empty? &&
          %w[ string boolean integer number ].include?(field["type"])
        raise AgentNative::Error.new("unsupported_input_schema", 422)
      end
      if field["enum"] && (!field["enum"].is_a?(Array) || field["enum"].empty? || field["enum"].size > 25)
        raise AgentNative::Error.new("unsupported_input_schema", 422)
      end
      %w[ minLength maxLength ].each do |key|
        raise AgentNative::Error.new("unsupported_input_schema", 422) if field[key] && (!field[key].is_a?(Integer) || !field[key].between?(0, 4096))
      end
      %w[ minimum maximum ].each do |key|
        raise AgentNative::Error.new("unsupported_input_schema", 422) if field[key] && !field[key].is_a?(Numeric)
      end
    end
  end

  def self.validate!(schema, input)
    validate_schema!(schema)
    properties = schema.fetch("properties", {}).transform_values { |field| field["type"] == "string" ? field.reverse_merge("maxLength" => 4096) : field }
    bounded = schema.merge("type" => "object", "properties" => properties, "additionalProperties" => false)
    raise AgentNative::Error.new("validation_failed", 422) unless AgentNative::Contract.valid?(bounded, input)
  end
end
