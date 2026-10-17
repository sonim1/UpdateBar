#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ruby -rfileutils -rjson -ropen3 -rpsych -rtmpdir - "$ROOT" <<'RUBY'
root = ARGV.fetch(0)
runner = File.join(root, "Scripts/app-e2e.sh")
abort "missing packaged app E2E runner" unless File.file?(runner)
%w[
  Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj/project.pbxproj
  Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj/xcshareddata/xcschemes/PackagedAppE2E.xcscheme
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

def validate_workflow(workflow)
  assert(workflow["name"] == "App E2E", "E2E workflow name must remain stable")
  assert(workflow["on"] == {
    "push" => nil,
    "pull_request" => { "branches" => ["main"] },
  }, "E2E must run for pushes and pull requests to main")
  assert(workflow["permissions"] == { "contents" => "read" }, "E2E must have read-only repository access")
  assert(workflow["concurrency"] == {
    "group" => "${{ github.workflow }}-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.ref }}",
    "cancel-in-progress" => true,
  }, "E2E must cancel superseded runs")
  assert(workflow.fetch("jobs").keys == ["packaged-app"], "E2E must have one serial app test job")
  job = workflow.fetch("jobs").fetch("packaged-app")
  assert(job.keys.sort == %w[runs-on steps timeout-minutes], "E2E must not bypass or tolerate test failures")
  assert(job["runs-on"] == "macos-15" && job["timeout-minutes"] == 15, "E2E must run on macOS with a bounded timeout")
  assert(job.fetch("steps") == [
    {
      "uses" => "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
      "with" => {
        "ref" => "${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}",
        "persist-credentials" => false,
      },
    },
    {
      "name" => "Package app for E2E",
      "env" => {
        "SPARKLE_PUBLIC_ED_KEY" => "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
        "UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE" => "1",
      },
      "run" => "bash Scripts/package-app.sh",
    },
    {
      "name" => "Test packaged app",
      "run" => 'bash Scripts/app-e2e.sh dist/UpdateBar.app "$RUNNER_TEMP/updatebar-app-e2e.xcresult"',
    },
    {
      "name" => "Upload E2E evidence",
      "if" => "${{ always() }}",
      "uses" => "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
      "with" => {
        "name" => "packaged-app-e2e-${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}",
        "path" => "${{ runner.temp }}/updatebar-app-e2e.xcresult",
        "if-no-files-found" => "warn",
        "retention-days" => 7,
      },
    },
  ], "E2E must package the real app, test the exact event SHA, and retain evidence even on failure")
end

workflow_path = File.join(root, ".github/workflows/app-e2e.yml")
assert(File.file?(workflow_path), "packaged app E2E workflow must exist")
workflow = Psych.safe_load(File.binread(workflow_path), permitted_classes: [], permitted_symbols: [], aliases: false)
validate_workflow(workflow)
[
  ->(value) { value["permissions"]["contents"] = "write" },
  ->(value) { value["jobs"]["packaged-app"]["continue-on-error"] = true },
  ->(value) { value["jobs"]["packaged-app"]["steps"][0]["with"]["ref"] = "${{ github.ref }}" },
  ->(value) { value["jobs"]["packaged-app"]["steps"][2]["run"] = "swift test" },
  ->(value) { value["jobs"]["packaged-app"]["steps"][3].delete("if") },
].each do |mutate|
  changed = Marshal.load(Marshal.dump(workflow))
  mutate.call(changed)
  begin
    validate_workflow(changed)
  rescue RuntimeError
    next
  end
  abort "FAIL: E2E workflow mutation was accepted"
end

puts "packaged app E2E runner and workflow tests passed"
RUBY
