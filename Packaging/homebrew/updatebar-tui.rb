# typed: strict
# frozen_string_literal: true

# Ink terminal UI companion formula for the UpdateBar CLI.
class UpdatebarTui < Formula
  desc "Ink terminal UI for UpdateBar"
  homepage "https://github.com/sonim1/UpdateBar"
  url "https://github.com/sonim1/UpdateBar/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "2a03c2c8ee0ebdc4fa3bad52f5348cfa73ece829fcc4b446160db89e2c9a431f"
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
    # Without a TTY the TUI renders once and exits 0.
    output = shell_output("#{bin}/updatebar-tui 2>&1")
    assert_match "UpdateBar", output
  end
end
