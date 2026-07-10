# frozen_string_literal: true

cask "updatebar-app" do
  version "0.3.1"
  sha256 "32a2ae9cdf0d37e0cb8c909d9a4537e959d3a61c94e75e9e90a61fe5f7d5da67"

  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  name "UpdateBar"
  desc "Menu bar update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "UpdateBar.app"

  zap trash: [
    "~/.updatebar",
    "~/Library/Logs/UpdateBar",
    "~/Library/Preferences/com.sonim1.UpdateBar.plist",
  ]

  caveats <<~EOS
    For the updatebar CLI, install the formula:
      brew install sonim1/tap/updatebar

    For the Open TUI menu item, install the terminal UI:
      brew install sonim1/tap/updatebar-tui
  EOS
end
