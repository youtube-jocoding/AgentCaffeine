# Homebrew cask 템플릿 — 배포 시작 후 placeholder를 채워서 사용
# 자신의 tap 저장소(예: github.com/<계정>/homebrew-tap)의 Casks/ 폴더에 두면
# brew install --cask <계정>/tap/agentcaffeine 으로 설치 가능
cask "agentcaffeine" do
  version "1.0"
  sha256 "PLACEHOLDER_SHA256" # notarize.sh 출력의 SHA256 값

  url "https://github.com/PLACEHOLDER_GITHUB/AgentCaffeine/releases/download/v#{version}/AgentCaffeine-#{version}.dmg"
  name "AgentCaffeine"
  desc "Keep your Mac awake while AI agents run — even with the lid closed"
  homepage "https://github.com/PLACEHOLDER_GITHUB/AgentCaffeine"

  app "AgentCaffeine.app"

  zap trash: [
    "~/Library/Preferences/com.jocoding.agentcaffeine.plist",
  ]
end
