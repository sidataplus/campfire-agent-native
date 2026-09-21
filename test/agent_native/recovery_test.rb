require "test_helper"
require_relative "../../lib/campfire/snapshot"

class AgentNativeRecoveryTest < ActiveSupport::TestCase
  test "epoch changes revoke credentials and do not silently enable dispatch" do
    original = ENV["CAMPFIRE_RECOVERY_EPOCH"]
    instance = AgentNative::Instance.current
    previous = instance.stream_epoch
    ENV["CAMPFIRE_RECOVERY_EPOCH"] = SecureRandom.hex(32)
    AgentNative::Maintenance.startup!
    assert instance.reload.recovery_required
    assert_not_equal previous, instance.stream_epoch
    assert_not instance.dispatch_allowed?
    assert_equal 0, Session.count
    assert AgentNative::MaintenanceAudit.where(operation: "epoch_changed").exists?
  ensure
    ENV["CAMPFIRE_RECOVERY_EPOCH"] = original
  end

  test "audit receipts cannot be overwritten through bulk SQL" do
    audit = AgentNative::MaintenanceAudit.create!(operation: "fixture", actor_id: "test", evidence_reference: "synthetic test", metadata: {})
    assert_raises(ActiveRecord::StatementInvalid) { AgentNative::MaintenanceAudit.where(id: audit.id).update_all(operation: "changed") }
  end

  test "snapshot authenticates bytes and restore requires a new epoch and empty target" do
    Dir.mktmpdir("agent-snapshot-") do |root|
      source = File.join(root, "source.sqlite3")
      files = File.join(root, "files")
      Dir.mkdir(files)
      db = SQLite3::Database.new(source)
      db.execute_batch(<<~SQL)
        CREATE TABLE schema_migrations(version TEXT);
        INSERT INTO schema_migrations VALUES('20260920215000');
        CREATE TABLE active_storage_blobs(key TEXT, byte_size INTEGER, checksum TEXT, service_name TEXT);
        CREATE TABLE sessions(id INTEGER);
        INSERT INTO sessions VALUES(1);
        CREATE TABLE agent_instances(id INTEGER, instance_uuid TEXT, stream_epoch TEXT, recovery_digest TEXT, recovery_required INTEGER, updated_at TEXT);
        CREATE TABLE agent_credentials(revoked_at TEXT, updated_at TEXT);
        CREATE TABLE agent_profiles(enabled INTEGER, authorization_version INTEGER, updated_at TEXT);
        CREATE TABLE agent_actions(state TEXT, version INTEGER, updated_at TEXT);
        CREATE TABLE agent_invocations(disposition TEXT, version INTEGER, updated_at TEXT);
        CREATE TABLE agent_runs(state TEXT, needs_reconciliation INTEGER, owner_generation INTEGER, version INTEGER, updated_at TEXT);
        CREATE TABLE agent_notifications(state TEXT, updated_at TEXT);
        INSERT INTO agent_runs VALUES('running',0,1,1,NULL);
        INSERT INTO agent_actions VALUES('pending',1,NULL);
      SQL
      epoch = SecureRandom.hex(32)
      db.execute("INSERT INTO agent_instances VALUES(1,'instance','epoch',?,0,NULL)", [ Digest::SHA256.hexdigest(epoch) ])
      key = "abcd1234fixture"
      content = (0..255).to_a.pack("C*") * 8193
      FileUtils.mkdir_p(File.join(files, "ab", "cd"))
      File.binwrite(File.join(files, "ab", "cd", key), content)
      db.execute("INSERT INTO active_storage_blobs VALUES(?,?,?,'local')", [ key, content.bytesize, Base64.strict_encode64(Digest::MD5.digest(content)) ])
      db.close
      snapshot = Campfire::Snapshot.new(secret: "s" * 64)
      backup = File.join(root, "backup")
      assert_raises(Campfire::Snapshot::Invalid) do
        snapshot.create!(database: source, files: files, destination: backup, recovery_epoch: SecureRandom.hex(32))
      end
      assert_not File.exist?(backup)
      snapshot.create!(database: source, files: files, destination: backup, recovery_epoch: epoch)
      assert_equal 2, snapshot.verify!(backup).fetch("files").size
      assert_raises(Campfire::Snapshot::Invalid) { Campfire::Snapshot.new(secret: "t" * 64).verify!(backup) }
      assert_raises(Campfire::Snapshot::Invalid) { snapshot.restore!(source: backup, destination: File.join(root, "bad"), recovery_epoch: epoch) }
      restored = File.join(root, "restored")
      snapshot.restore!(source: backup, destination: restored, recovery_epoch: SecureRandom.hex(32))
      restored_db = SQLite3::Database.new(File.join(restored, "db", "source.sqlite3"))
      assert_equal 0, restored_db.get_first_value("SELECT COUNT(*) FROM sessions")
      assert_equal 1, restored_db.get_first_value("SELECT recovery_required FROM agent_instances")
      assert_equal [ 1, 2 ], restored_db.get_first_row("SELECT needs_reconciliation, owner_generation FROM agent_runs")
      assert_equal "invalidated", restored_db.get_first_value("SELECT state FROM agent_actions")
      restored_db.close
      assert_equal content, File.binread(File.join(restored, "files", "ab", "cd", key))
      assert_raises(Campfire::Snapshot::Invalid) { snapshot.restore!(source: backup, destination: restored, recovery_epoch: SecureRandom.hex(32)) }
      File.write(File.join(backup, "files", "ab", "cd", key), "tampered")
      assert_raises(Campfire::Snapshot::Invalid) { snapshot.verify!(backup) }
    end
  end
end
