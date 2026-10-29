# TEMPLATE: scripts/bump-tap.sh fills in __VERSION__ and __SHA256__ from a published release and writes the result to
# mpdreamz/homebrew-tap as Casks/reel.rb.
cask "reel" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/mpdreamz/reel/releases/download/v#{version}/reel-arm64.zip"
  name "reel"
  desc "Record app and web page demos from a script, with sound"
  homepage "https://github.com/mpdreamz/reel"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia

  binary "reel"

  caveats <<~EOS
    reel records with Screen Recording and drives apps with Accessibility, both granted to the terminal it runs in:
    `reel doctor` says what is missing. Web pages need nothing more; WebKit is built in.
  EOS
end
