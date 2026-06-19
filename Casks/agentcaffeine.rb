# Homebrew cask 템플릿 — 배포 시작 후 placeholder를 채워서 사용
# 자신의 tap 저장소(예: github.com/<계정>/homebrew-tap)의 Casks/ 폴더에 두면
# brew install --cask <계정>/tap/agentcaffeine 으로 설치 가능
cask "agentcaffeine" do
  version "1.0.2"
  sha256 "5901d71f9b9336829ed70d24e209f02eb899bd80492fa2f91050d3829c5dbdee"

  url "https://github.com/youtube-jocoding/AgentCaffeine/releases/download/v#{version}/AgentCaffeine-#{version}.dmg"
  name "AgentCaffeine"
  desc "Keep your Mac awake while AI agents run — even with the lid closed"
  homepage "https://github.com/youtube-jocoding/AgentCaffeine"

  app "AgentCaffeine.app"

  zap trash: [
    "~/Library/Preferences/com.jocoding.agentcaffeine.plist",
  ]
end
