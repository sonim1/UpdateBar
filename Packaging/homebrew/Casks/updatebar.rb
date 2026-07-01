# frozen_string_literal: true

cask "updatebar" do
  version "0.2.0"
  sha256 "aaa8f0d8948d2f08992ce0409d5df552dac55f8a8fedeb54d7f5297c50d69b56"

  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  name "UpdateBar"
  desc "Menu bar update tracker for local tools"
  homepage "https://github.com/sonim1/UpdateBar"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "UpdateBar.app"

  caveats <<~EOS
    UpdateBar.app is currently unsigned. If macOS blocks the first launch,
    Control-click UpdateBar.app in Finder, choose Open, then confirm Open.

    For the updatebar CLI, install the formula:
      brew install sonim1/tap/updatebar
  EOS

  zap trash: [
    "~/.updatebar",
    "~/Library/Logs/UpdateBar",
    "~/Library/Preferences/com.sonim1.UpdateBar.plist",
  ]
end
