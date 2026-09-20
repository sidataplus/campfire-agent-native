require_relative "../../lib/campfire/sqlite_trigger_schema"

# Rails' Ruby dumper handles FTS virtual tables without duplicating shadow tables.
# The narrow extension preserves our migration-owned triggers in schema clones.
Rails.application.config.active_record.schema_format = :ruby
ActiveRecord::SchemaDumper.prepend Campfire::SQLiteTriggerSchema
