# typed: strict
# frozen_string_literal: true

# Formula for UpdateBar.
class Updatebar < Formula
  desc "CLI-first update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"
  version "0.1.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/sonim1/UpdateBar/releases/download/v0.1.0/updatebar-0.1.0-macos-arm64.tar.gz"
      sha256 "bb5291c5d4e67cc35aa697e9348b5d1995a4ae5f1a2d157964cadc6477d1cb75"
    end
  end

  def install
    bin.install "updatebar"
  end

  test do
    assert_match "\"version\":\"#{version}\"", shell_output("#{bin}/updatebar version --json")
  end
end
