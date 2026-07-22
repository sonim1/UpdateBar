# frozen_string_literal: true

cask "updatebar-app" do
  version "0.6.1"
  sha256 "d7a375e9f3d7f855317d841fd0358c8caa20d4a5e1090cb87a5f733fb479fd69"

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
