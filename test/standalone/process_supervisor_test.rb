require "minitest/autorun"
require "tmpdir"
require "rbconfig"
require "timeout"
require "json"

class ProcessSupervisorTest < Minitest::Test
  LIBRARY = File.expand_path("../../lib/campfire/process_supervisor", __dir__)

  def run_fixture(prepare_exit: 0, check_exit: 0, probe: "true", redis_exit: nil, web_exit: nil, stop: true)
    Dir.mktmpdir do |root|
      log = File.join(root, "events")
      worker = File.join(root, "worker.rb")
      File.write(worker, <<~RUBY)
        File.open(ENV.fetch("TEST_LOG"), "a") { |f| f.puts ARGV[0] }
        exit ARGV[1].to_i if ARGV[1] != "wait"
        trap("TERM") { exit 0 }
        loop { sleep 0.05 }
      RUBY
      command = ->(name, code) { [ RbConfig.ruby, worker, name, code.nil? ? "wait" : code.to_s ] }
      runner = File.join(root, "runner.rb")
      File.write(runner, <<~RUBY)
        require #{LIBRARY.inspect}
        exit Campfire::ProcessSupervisor.new(
          commands: #{ { "redis" => command.call("redis", redis_exit), "web" => command.call("web", web_exit), "workers" => command.call("workers", nil) }.inspect },
          prepare: #{command.call("prepare", prepare_exit).inspect},
          after_prepare: #{command.call("check", check_exit).inspect},
          probe: -> { #{probe} }, timeout: 0.25, grace: 0.25
        ).run
      RUBY
      output = File.join(root, "output")
      pid = Process.spawn({ "TEST_LOG" => log }, RbConfig.ruby, runner, out: output, err: output)
      if stop
        Timeout.timeout(10) do
          loop do
            events = File.exist?(log) ? File.readlines(log, chomp: true) : []
            break if %w[ redis prepare check workers web ].all? { |name| events.include?(name) }
            sleep 0.02
          end
        end
        Process.kill("TERM", pid)
      end
      status = Timeout.timeout(5) { Process.waitpid2(pid).last }
      events = File.exist?(log) ? File.readlines(log, chomp: true) : []
      yield events, status, File.read(output)
    ensure
      if pid
        Process.kill("KILL", pid) rescue nil
        Process.waitpid(pid) rescue nil
      end
    end
  end

  def test_preparation_precedes_workers_and_web
    run_fixture do |events, status, _|
      assert status.success?
      assert_operator events.index("prepare"), :<, events.index("check")
      assert_operator events.index("check"), :<, events.index("workers")
      assert_operator events.index("check"), :<, events.index("web")
    end
  end

  def test_failed_migration_never_starts_workers_or_web
    run_fixture(prepare_exit: 1, stop: false) do |events, status, output|
      refute status.success?
      refute_includes events, "workers"
      refute_includes events, "web"
      refute_includes events, "check"
      assert_includes output, "prepare exited"
    end
  end

  def test_failed_bootstrap_check_never_serves
    run_fixture(check_exit: 1, stop: false) do |events, status, _|
      refute status.success?
      refute_includes events, "web"
      refute_includes events, "workers"
    end
  end

  def test_dependency_timeout_is_fatal
    run_fixture(probe: "false", stop: false) do |events, status, output|
      refute status.success?
      refute_includes events, "prepare"
      assert_includes output, "Redis readiness timed out"
    end
  end

  def test_even_clean_unexpected_web_exit_is_fatal
    run_fixture(web_exit: 0, stop: false) do |_, status, output|
      refute status.success?
      assert_includes output, "web exited unexpectedly"
    end
  end
end
