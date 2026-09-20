JSON.parse(Rails.root.join("config/agent_native_operations.json").read).each do |entry|
  match entry.fetch("path").gsub(/\{([^}]+)\}/, ':\1'),
    to: "agent_native/api##{entry.fetch('operation_id').underscore}",
    via: entry.fetch("method").downcase.to_sym, defaults: { format: :json }
end
