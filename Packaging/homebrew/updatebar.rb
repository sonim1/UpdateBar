# typed: strict
# frozen_string_literal: true

# Formula for UpdateBar.
class Updatebar < Formula
  desc "CLI-first update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"
  url "https://github.com/sonim1/UpdateBar/releases/download/v0.3.2/updatebar-0.3.2-macos-arm64.tar.gz"
  version "0.3.2"
  sha256 "63ca9d1b03d1fb7cf3582e208b504be652b89e00fddec86a816e95b7a020d521"

  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    bin.install "updatebar"
  end

  test do
    assert_match version, shell_output("#{bin}/updatebar --version").strip
  end
end
