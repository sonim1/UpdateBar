#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ruby -rfileutils -rjson -ropen3 -rtmpdir - "$ROOT" <<'RUBY'
root = ARGV.fetch(0)
runner = File.join(root, "Scripts/app-e2e.sh")
abort "missing packaged app E2E runner" unless File.file?(runner)
%w[
  Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj/project.pbxproj
  Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj/xcshareddata/xcschemes/PackagedAppE2E.xcscheme
  Tests/PackagedAppE2E/PackagedAppE2E-Info.plist
].each do |path|
  abort "missing E2E test project input: #{path}" unless File.file?(File.join(root, path))
end

def assert(value, message)
  raise "FAIL: #{message}" unless value
end

Dir.mktmpdir("updatebar-app-e2e-contract") do |temporary|
  workspace = File.join(temporary, "workspace with spaces")
  scripts = File.join(workspace, "Scripts")
  bin = File.join(temporary, "bin")
  FileUtils.mkdir_p([scripts, bin])
  FileUtils.cp(runner, File.join(scripts, "app-e2e.sh"))
  File.write(File.join(bin, "uname"), "#!/bin/sh\nprintf 'Darwin\\n'\n")
  File.write(File.join(bin, "xcodebuild"), <<~'STUB')
    #!/usr/bin/env ruby
    require "fileutils"
    require "json"
    File.write(ENV.fetch("E2E_CONTRACT_CALLS"), JSON.generate(ARGV))
    path = ARGV.fetch(ARGV.index("-resultBundlePath") + 1)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "result-marker"), "test evidence")
    exit Integer(ENV.fetch("E2E_CONTRACT_EXIT", "0"))
  STUB
  FileUtils.chmod(0o755, [File.join(bin, "uname"), File.join(bin, "xcodebuild")])
  calls = File.join(temporary, "calls.json")
  environment = {
    "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
    "E2E_CONTRACT_CALLS" => calls,
  }
  command = ["bash", File.join(scripts, "app-e2e.sh")]

  _, stderr, status = Open3.capture3(environment, *command, File.join(temporary, "missing.app"))
  assert(!status.success? && stderr.include?("packaged UpdateBar.app"), "missing bundle must fail with an actionable error")
  assert(!File.exist?(calls), "missing bundle must not invoke Xcode")

  app = File.join(temporary, "app with spaces", "UpdateBar.app")
  %w[Contents/MacOS/UpdateBar Contents/Resources/updatebar].each do |relative|
    path = File.join(app, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end
  result = File.join(temporary, "results with spaces", "success.xcresult")
  _, stderr, status = Open3.capture3(environment, *command, app, result)
  assert(status.success?, "valid packaged app must invoke Xcode: #{stderr}")
  arguments = JSON.parse(File.read(calls))
  {
    "-project" => File.join(workspace, "Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj"),
    "-scheme" => "PackagedAppE2E",
    "-destination" => "platform=macOS",
    "-resultBundlePath" => File.realpath(result),
    "-parallel-testing-enabled" => "NO",
  }.each do |flag, value|
    index = arguments.index(flag)
    assert(index && arguments[index + 1] == value, "#{flag} must preserve its complete argument")
  end
  assert(arguments.include?("test"), "runner must execute tests, not just build")
  assert(arguments.include?("UPDATEBAR_E2E_APP_PATH=#{File.realpath(app)}"), "runner must select the supplied packaged app without splitting its path")
  assert(File.read(File.join(result, "result-marker")) == "test evidence", "successful test evidence must remain available")

  failed = File.join(temporary, "failure.xcresult")
  _, _, status = Open3.capture3(environment.merge("E2E_CONTRACT_EXIT" => "34"), *command, app, failed)
  assert(status.exitstatus == 34, "failed UI tests must propagate Xcode's exit status")
  assert(File.file?(File.join(failed, "result-marker")), "failed test evidence must remain available")

  FileUtils.rm_f(calls)
  _, stderr, status = Open3.capture3(environment, *command, app, result)
  assert(!status.success? && stderr.include?("already exists"), "existing results must not be overwritten")
  assert(!File.exist?(calls), "existing results must be rejected before invoking Xcode")
end

puts "packaged app E2E runner tests passed"
RUBY
