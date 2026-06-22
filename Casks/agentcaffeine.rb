# Homebrew cask for AgentCaffeine releases.
cask "agentcaffeine" do
  version "1.0.3"
  sha256 "c3cc2ec885b4226abab76c6a404459e200360efdb0aad61bea594d98324b5df3"

  url "https://github.com/youtube-jocoding/AgentCaffeine/releases/download/v#{version}/AgentCaffeine-#{version}.dmg"
  name "AgentCaffeine"
  desc "Keep your Mac awake while AI agents run — even with the lid closed"
  homepage "https://github.com/youtube-jocoding/AgentCaffeine"

  app "AgentCaffeine.app"

  zap trash: [
    "~/Library/Preferences/com.jocoding.agentcaffeine.plist",
  ]
end
