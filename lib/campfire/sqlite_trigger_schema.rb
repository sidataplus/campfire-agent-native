module Campfire
  module SqliteTriggerSchema
    private
      def trailer(stream)
        if @connection.adapter_name == "SQLite"
          sql = "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name GLOB 'agent_*' ORDER BY name"
          @connection.select_values(sql).each { |definition| stream.puts "  execute #{definition.inspect}" }
        end
        super
      end
  end
  # Preserve the explicit initializer reference while honoring Zeitwerk inflection.
  SQLiteTriggerSchema = SqliteTriggerSchema
end
