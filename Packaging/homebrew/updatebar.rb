# typed: strict
# frozen_string_literal: true

# Formula for UpdateBar.
class Updatebar < Formula
  desc "CLI-first update tracker for local tools"
  homepage "https://github.com/kendrick/UpdateBar"
  version "0.1.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/kendrick/UpdateBar/releases/download/v0.1.0/updatebar-0.1.0-macos-arm64.tar.gz"
      sha256 "aa8aa9bf844cfe462f6f7abfb83e2b12bf45bb265419d580dd0fb3e60c66bb68"
    end
  end

  def install
    bin.install "updatebar"
  end

  test do
    assert_match "\"version\":\"#{version}\"", shell_output("#{bin}/updatebar version --json")
  end
end
