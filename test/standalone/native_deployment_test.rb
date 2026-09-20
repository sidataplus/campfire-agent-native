require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/campfire/deployment"

class NativeDeploymentTest < Minitest::Test
  def test_incomplete_restore_is_never_bootable
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "storage"))
      File.write(File.join(root, "storage", ".campfire-restore-incomplete"), "incomplete")
      error = assert_raises(Campfire::Deployment::Invalid) { Campfire::Deployment.new.check_storage!(root) }
      assert_includes error.message, "incomplete restore"
    end
  end
end
