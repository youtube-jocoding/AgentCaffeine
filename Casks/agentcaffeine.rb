# Homebrew cask for AgentCaffeine releases.
cask "agentcaffeine" do
  version "1.0.4"
  sha256 "8b19ba378bc4d26b325b181da300d0c149c3e2d914b7c918bd0d4456407e255e"

  url "https://github.com/youtube-jocoding/AgentCaffeine/releases/download/v#{version}/AgentCaffeine-#{version}.dmg"
  name "AgentCaffeine"
  desc "Keep your Mac awake while AI agents run — even with the lid closed"
  homepage "https://github.com/youtube-jocoding/AgentCaffeine"

  app "AgentCaffeine.app"

  zap trash: [
    "~/Library/Preferences/com.jocoding.agentcaffeine.plist",
  ]
end
