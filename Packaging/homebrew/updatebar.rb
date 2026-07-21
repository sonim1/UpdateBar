# typed: strict
# frozen_string_literal: true

# Formula for UpdateBar.
class Updatebar < Formula
  desc "CLI-first update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"
  url "https://github.com/sonim1/UpdateBar/releases/download/v0.5.0/updatebar-0.5.0-macos-arm64.tar.gz"
  version "0.5.0"
  sha256 "29aa7ca8b74c85162c6bb5b983ac58597028d3aba53de5b2e8bc273c44a2636f"

  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    bin.install "updatebar"
  end

  test do
    assert_match version, shell_output("#{bin}/updatebar --version").strip
  end
end
