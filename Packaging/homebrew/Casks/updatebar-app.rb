# frozen_string_literal: true

cask "updatebar-app" do
  version "0.5.0"
  sha256 "7ba5e918c4f1592fde4e557cdcf5f93823bad53bf9b7835e8cca671e88cc1f63"

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
