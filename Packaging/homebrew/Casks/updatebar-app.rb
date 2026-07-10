# frozen_string_literal: true

cask "updatebar-app" do
  version "0.3.0"
  sha256 "aaa8f0d8948d2f08992ce0409d5df552dac55f8a8fedeb54d7f5297c50d69b56"

  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  name "UpdateBar"
  desc "Menu bar update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "UpdateBar.app"

  caveats <<~EOS
    This app is currently unsigned. On macOS 15 or newer, if Gatekeeper
    blocks the first launch, open System Settings > Privacy & Security and
    choose Open Anyway for UpdateBar.app. On older macOS versions,
    Control-click Open may still work.

    For the updatebar CLI, install the formula:
      brew install sonim1/tap/updatebar

    For the Open TUI menu item, install the terminal UI:
      brew install sonim1/tap/updatebar-tui
  EOS

  zap trash: [
    "~/.updatebar",
    "~/Library/Logs/UpdateBar",
    "~/Library/Preferences/com.sonim1.UpdateBar.plist",
  ]
end
