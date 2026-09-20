require "socket"
require "yaml"

module Campfire
  # One replica, one process group per service. Unexpected service exit is fatal.
  class ProcessSupervisor
    class Failure < StandardError; end
    class Stopped < StandardError; end

    def initialize(commands:, prepare:, after_prepare:, probe: nil, timeout: 30, grace: 10)
      @commands, @prepare, @after_prepare = commands, prepare, after_prepare
      @probe = probe || method(:redis_ready?)
      @timeout, @grace = timeout, grace
      @children, @groups = {}, []
      @stopping = false
    end

    def run
      %w[ INT TERM ].each { |signal| Signal.trap(signal) { @stopping = true } }
      start("redis", @commands.fetch("redis"))
      deadline = monotonic + @timeout
      until @probe.call
        check_children!
        raise Failure, "Redis readiness timed out" if monotonic >= deadline
        pause
      end
      prepare = start("prepare", @prepare)
      wait_success!(prepare)
      check = start("bootstrap-check", @after_prepare)
      wait_success!(check)
      start("workers", @commands.fetch("workers"))
      start("web", @commands.fetch("web"))
      loop { check_children!; pause }
    rescue Stopped
      0
    rescue Failure, SystemCallError, KeyError => error
      warn "Campfire supervisor failed: #{error.class}: #{error.message}"
      1
    ensure
      shutdown
      %w[ INT TERM ].each { |signal| Signal.trap(signal, "DEFAULT") }
    end

    private
      def start(name, command)
        pid = Process.spawn(*Array(command), pgroup: true)
        @children[pid] = name
        @groups << pid
        pid
      end

      def wait_success!(target)
        loop do
          check_stop!
          @children.keys.each do |pid|
            result = Process.waitpid2(pid, Process::WNOHANG)
            next unless result
            name = @children.delete(pid)
            raise Failure, "#{name} exited before startup completed" unless pid == target && result.last.success?
            signal_group("TERM", pid)
            signal_group("KILL", pid)
            @groups.delete(pid)
            return
          end
          pause
        end
      end

      def check_children!
        check_stop!
        @children.keys.each do |pid|
          if Process.waitpid2(pid, Process::WNOHANG)
            name = @children.delete(pid)
            raise Failure, "#{name} exited unexpectedly"
          end
        end
      end

      def check_stop!
        raise Stopped if @stopping
      end

      def pause
        check_stop!
        sleep 0.05
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def redis_ready?
        Socket.tcp("127.0.0.1", 6379, connect_timeout: 1) do |socket|
          socket.write("*1\r\n$4\r\nPING\r\n")
          IO.select([ socket ], nil, nil, 1) && socket.readpartial(64).start_with?("+PONG\r\n")
        end
      rescue SystemCallError, IOError, EOFError
        false
      end

      def shutdown
        # Keep groups after their leaders exit, so descendants are also stopped.
        @groups.each { |pid| signal_group("TERM", pid) }
        deadline = monotonic + @grace
        until @children.empty? || monotonic >= deadline
          @children.keys.each do |pid|
            @children.delete(pid) if Process.waitpid(pid, Process::WNOHANG)
          rescue Errno::ECHILD
            @children.delete(pid)
          end
          sleep 0.05 unless @children.empty?
        end
        @groups.each { |pid| signal_group("KILL", pid) }
        @children.each_key do |pid|
          Process.waitpid(pid)
        rescue Errno::ECHILD
          nil
        end
      end

      def signal_group(signal, pid)
        Process.kill(signal, -pid)
      rescue Errno::ESRCH
        nil
      end
  end
end
