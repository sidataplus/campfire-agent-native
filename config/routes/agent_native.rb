Dir[Rails.root.join("config/agent_native*_operations.json")].sort.each do |file|
  JSON.parse(File.read(file)).each do |entry|
    controller = entry["human_only"] ? "human" : "api"
    match entry.fetch("path").gsub(/\{([^}]+)\}/, ':\1'),
      to: "agent_native/#{controller}##{entry.fetch('operation_id').underscore}",
      via: entry.fetch("method").downcase.to_sym, defaults: { format: :json }
  end
end
post "/agent/rooms/:room_id/invocations", to: "agent_native/human#create_invocation", defaults: { format: :json }
