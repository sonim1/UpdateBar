# typed: strict
# frozen_string_literal: true

# Formula for UpdateBar.
class Updatebar < Formula
  desc "CLI-first update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"
  url "https://github.com/sonim1/UpdateBar/releases/download/v0.3.1/updatebar-0.3.1-macos-arm64.tar.gz"
  version "0.3.1"
  sha256 "7d25b6d98a697165eeb0a93ce9678742101bb4662fb4008350823acf9903d45b"

  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    bin.install "updatebar"
  end

  test do
    assert_match version, shell_output("#{bin}/updatebar --version").strip
  end
end
