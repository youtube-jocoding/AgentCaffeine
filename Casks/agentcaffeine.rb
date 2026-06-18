# Homebrew cask 템플릿 — 배포 시작 후 placeholder를 채워서 사용
# 자신의 tap 저장소(예: github.com/<계정>/homebrew-tap)의 Casks/ 폴더에 두면
# brew install --cask <계정>/tap/agentcaffeine 으로 설치 가능
cask "agentcaffeine" do
  version "1.0.1"
  sha256 "598d0a0ca598c569bc20c25fe2f7ce8fbd3e81c1dd663b9c887155ce90d2473f"

  url "https://github.com/youtube-jocoding/AgentCaffeine/releases/download/v#{version}/AgentCaffeine-#{version}.dmg"
  name "AgentCaffeine"
  desc "Keep your Mac awake while AI agents run — even with the lid closed"
  homepage "https://github.com/youtube-jocoding/AgentCaffeine"

  app "AgentCaffeine.app"

  zap trash: [
    "~/Library/Preferences/com.jocoding.agentcaffeine.plist",
  ]
end
