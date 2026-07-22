# typed: strict
# frozen_string_literal: true

# Ink terminal UI companion formula for the UpdateBar CLI.
class UpdatebarTui < Formula
  desc "Ink terminal UI for UpdateBar"
  homepage "https://github.com/sonim1/UpdateBar"
  url "https://github.com/sonim1/UpdateBar/archive/refs/tags/v0.6.0.tar.gz"
  sha256 "6a054c8e2966681198c7a6f0ac8e61da2a62c4eb16576d966d0ac58c31aec68e"
  license "MIT"

  depends_on "node"

  def install
    cd "tui" do
      system "npm", "ci", *std_npm_args(prefix: false)
      system "npm", "run", "build"
      system "npm", "prune", "--omit=dev"
      libexec.install "dist", "node_modules", "package.json"
    end
    bin.install_symlink libexec/"dist/index.js" => "updatebar-tui"
  end

  def caveats
    <<~EOS
      updatebar-tui talks to the updatebar CLI. Install it with:
        brew install sonim1/tap/updatebar
    EOS
  end

  test do
    assert_predicate bin/"updatebar-tui", :executable?
  end
end
