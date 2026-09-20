require "base64"
require "digest"
require "fileutils"
require "json"
require "openssl"
require "securerandom"
require "sqlite3"
require "time"

module Campfire
  # Backups are authenticated, not encrypted. Keep the original instance key off-volume.
  class Snapshot
    class Invalid < StandardError; end
    MANIFEST = "snapshot.json"
    INCOMPLETE = ".campfire-restore-incomplete"
    MAX_FILES = 100_000

    def initialize(secret: ENV.fetch("SECRET_KEY_BASE", ""))
      raise Invalid, "The original instance SECRET_KEY_BASE is required" if secret.bytesize < 64
      @key = OpenSSL::HMAC.digest("SHA256", secret, "agent-campfire-snapshot-v1")
    end

    def create!(database:, files:, destination:, recovery_epoch:, fingerprints: nil)
      source = File.expand_path(database)
      root = File.expand_path(files)
      target = File.expand_path(destination)
      validate_existing!(source, directory: false)
      validate_existing!(root, directory: true)
      raise Invalid, "Backup destination must be new and outside upload storage" if File.exist?(target) || File.symlink?(target) || target.start_with?(root + "/")
      validate_existing!(File.dirname(target), directory: true)
      epoch!(recovery_epoch)
      stage = target + ".partial-#{SecureRandom.hex(12)}"
      Dir.mkdir(stage, 0o700)
      db_name = File.basename(source)
      raise Invalid, "Unsupported database filename" unless db_name.match?(/\A[a-zA-Z0-9_.-]+\.sqlite3\z/)
      FileUtils.mkdir_p(File.join(stage, "db"), mode: 0o700)
      copy_db = File.join(stage, "db", db_name)
      with_database(source, readonly: true) do |db|
        db.busy_timeout = 10_000
        db.execute("VACUUM INTO ?", [ copy_db ])
      end
      File.chmod(0o600, copy_db)
      entries = [ file_entry(stage, "db/#{db_name}") ]
      metadata = with_database(copy_db, readonly: true) do |db|
        check_database!(db)
        blobs = db.execute("SELECT key, byte_size, checksum, service_name FROM active_storage_blobs")
        raise Invalid, "Snapshot file limit exceeded" if blobs.size > MAX_FILES
        blobs.each do |key, size, checksum, service|
          raise Invalid, "Only local Disk storage can be snapshotted" unless %w[ local test ].include?(service)
          raise Invalid, "Unsafe storage key" unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_-]{8,128}\z/)
          relative = "files/#{key[0, 2]}/#{key[2, 2]}/#{key}"
          from = File.join(root, key[0, 2], key[2, 2], key)
          entry = copy_checked!(from, stage, relative)
          raise Invalid, "A blob changed or disappeared during backup; retry in a quiet period" unless entry["size"] == size && (!checksum || checksum == entry.delete("md5"))
          entry.delete("md5")
          entries << entry
        end
        {
          "schema_version" => db.get_first_value("SELECT MAX(version) FROM schema_migrations"),
          "instance" => db.get_first_row("SELECT instance_uuid, stream_epoch, recovery_digest FROM agent_instances WHERE id=1")
        }
      end
      if fingerprints && File.exist?(fingerprints)
        entries << copy_checked!(fingerprints, stage, ".campfire-secret-fingerprints.json").except("md5")
      end
      payload = { "format" => 1, "created_at" => Time.now.utc.iso8601, "database" => "db/#{db_name}",
        "recovery_digest" => Digest::SHA256.hexdigest(recovery_epoch), "metadata" => metadata, "files" => entries }
      document = { "payload" => payload, "hmac_sha256" => signature(payload) }
      exclusive_write(File.join(stage, MANIFEST), JSON.generate(document) + "\n")
      verify!(stage)
      File.rename(stage, target)
      fsync_directory(File.dirname(target))
      payload
    rescue StandardError
      FileUtils.remove_entry_secure(stage) if stage && File.directory?(stage) && !File.symlink?(stage)
      raise
    end

    def verify!(source)
      root = File.expand_path(source)
      validate_existing!(root, directory: true)
      manifest_path = File.join(root, MANIFEST)
      validate_existing!(manifest_path, directory: false)
      raise Invalid, "Snapshot manifest exceeds limit" if File.size(manifest_path) > 16_777_216
      document = JSON.parse(File.read(manifest_path))
      payload, mac = document.fetch("payload"), document.fetch("hmac_sha256")
      expected = signature(payload)
      raise Invalid, "Snapshot authentication failed" unless mac.is_a?(String) && mac.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(mac, expected)
      raise Invalid, "Unsupported snapshot format" unless payload["format"] == 1
      entries = payload.fetch("files")
      raise Invalid, "Invalid snapshot file list" unless entries.is_a?(Array) && entries.size.between?(1, MAX_FILES + 2) && entries.map { |e| e["path"] }.uniq.size == entries.size
      entries.each do |entry|
        relative = entry.fetch("path")
        safe_relative!(relative)
        path = File.join(root, relative)
        validate_existing!(path, directory: false)
        raise Invalid, "Snapshot checksum or size mismatch" unless File.size(path) == entry.fetch("size") && Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
      end
      raise Invalid, "Snapshot database is not listed" unless entries.any? { |entry| entry["path"] == payload.fetch("database") }
      raise Invalid, "Invalid database location" unless payload["database"].match?(/\Adb\/[a-zA-Z0-9_.-]+\.sqlite3\z/)
      with_database(File.join(root, payload["database"]), readonly: true) { |db| check_database!(db) }
      payload
    rescue JSON::ParserError, KeyError, TypeError
      raise Invalid, "Snapshot manifest is malformed"
    end

    # Restoration only writes into a new/empty volume and leaves dispatch quarantined.
    def restore!(source:, destination:, recovery_epoch:)
      epoch!(recovery_epoch)
      payload = verify!(source)
      raise Invalid, "Restore requires a new deployment-held recovery epoch" if Digest::SHA256.hexdigest(recovery_epoch) == payload.fetch("recovery_digest")
      target = File.expand_path(destination)
      Dir.mkdir(target, 0o700) unless File.exist?(target)
      validate_existing!(target, directory: true)
      raise Invalid, "Restore target must be empty; live volumes are never overwritten" unless Dir.children(target).empty?
      exclusive_write(File.join(target, INCOMPLETE), "Restore in progress. Do not start the application.\n")
      payload.fetch("files").each do |entry|
        copied = copy_checked!(File.join(source, entry["path"]), target, entry["path"])
        raise Invalid, "Snapshot changed during restore" unless copied["sha256"] == entry["sha256"] && copied["size"] == entry["size"]
      end
      with_database(File.join(target, payload.fetch("database"))) do |db|
        quarantine!(db, recovery_epoch)
        check_database!(db)
      end
      File.unlink(File.join(target, INCOMPLETE))
      fsync_directory(target)
      { "restored" => true, "recovery_required" => true, "dispatch_enabled" => false }
    end

    def quarantine!(db, epoch)
      now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
      db.transaction do
        db.execute("DELETE FROM sessions")
        db.execute("UPDATE agent_credentials SET revoked_at=?, updated_at=?", [ now, now ])
        db.execute("UPDATE agent_profiles SET enabled=0, authorization_version=authorization_version+1, updated_at=?", [ now ])
        db.execute("UPDATE agent_actions SET state='invalidated', version=version+1, updated_at=? WHERE state='pending'", [ now ])
        db.execute("UPDATE agent_invocations SET disposition='invalidated', version=version+1, updated_at=? WHERE disposition='pending'", [ now ])
        db.execute("UPDATE agent_runs SET needs_reconciliation=1, owner_generation=owner_generation+1, version=version+1, updated_at=? WHERE state NOT IN ('completed','failed','cancelled','expired')", [ now ])
        db.execute("UPDATE agent_notifications SET state='discarded', updated_at=? WHERE state != 'sent'", [ now ])
        db.execute("UPDATE agent_instances SET recovery_required=1, recovery_digest=?, stream_epoch=?, updated_at=? WHERE id=1", [ Digest::SHA256.hexdigest(epoch), SecureRandom.uuid, now ])
      end
    end

    private
      def epoch!(epoch)
        raise Invalid, "Recovery epoch must be an independent random 32-128 character identifier" unless epoch.is_a?(String) && epoch.match?(/\A[A-Za-z0-9_-]{32,128}\z/)
      end

      def signature(payload)
        OpenSSL::HMAC.hexdigest("SHA256", @key, JSON.generate(payload))
      end

      def safe_relative!(path)
        unless path.is_a?(String) && path.match?(/\A(?:db\/[a-zA-Z0-9_.-]+\.sqlite3|files\/[a-zA-Z0-9_-]{2}\/[a-zA-Z0-9_-]{2}\/[a-zA-Z0-9_-]{8,128}|\.campfire-secret-fingerprints\.json)\z/)
          raise Invalid, "Unsafe snapshot path"
        end
      end

      def validate_existing!(path, directory:)
        absolute = File.expand_path(path)
        parts = absolute.split("/").reject(&:empty?)
        current = "/"
        parts.each do |part|
          current = File.join(current, part)
          raise Invalid, "Symlinks are not accepted in snapshot paths" if File.symlink?(current)
        end
        info = File.lstat(absolute)
        raise Invalid, "Expected a regular file or directory" unless directory ? info.directory? : info.file?
      end

      def with_database(path, readonly: false)
        flags = readonly ? SQLite3::Constants::Open::READONLY : SQLite3::Constants::Open::READWRITE
        db = SQLite3::Database.new(path, flags: flags)
        db.busy_timeout = 10_000
        yield db
      ensure
        db&.close
      end

      def check_database!(db)
        raise Invalid, "SQLite integrity check failed" unless db.get_first_value("PRAGMA quick_check") == "ok"
        raise Invalid, "SQLite foreign key check failed" unless db.execute("PRAGMA foreign_key_check").empty?
      end

      def copy_checked!(source, destination, relative)
        safe_relative!(relative)
        validate_existing!(source, directory: false)
        target = File.join(destination, relative)
        FileUtils.mkdir_p(File.dirname(target), mode: 0o700)
        sha, md5, size = Digest::SHA256.new, Digest::MD5.new, 0
        File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
          raise Invalid, "Snapshot source is not a regular file" unless input.stat.file?
          File.open(target, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |output|
            while chunk = input.read(1_048_576)
              output.write(chunk)
              sha.update(chunk)
              md5.update(chunk)
              size += chunk.bytesize
            end
            output.flush
            output.fsync
          end
        end
        { "path" => relative, "size" => size, "sha256" => sha.hexdigest, "md5" => Base64.strict_encode64(md5.digest) }
      end

      def file_entry(root, relative)
        path = File.join(root, relative)
        File.open(path) { |file| file.fsync }
        { "path" => relative, "size" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
      end

      def exclusive_write(path, contents)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(contents)
          file.flush
          file.fsync
        end
      end

      def fsync_directory(path)
        File.open(path, File::RDONLY) { |directory| directory.fsync }
      end
  end
end
