class Spider < Formula
  desc "Spider Cleaner - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/spider"
  license "MIT"
  version "1.0.0"

  # Install latest main branch (recommended until you cut a release)
  head "https://github.com/anshpatelkb/spider.git", branch: "main"

  # Stable install after you create tag v1.0.0 and fill in sha256:
  #   curl -sL https://github.com/anshpatelkb/spider/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
  url "https://github.com/anshpatelkb/spider/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_AFTER_TAGGING_V1_0_0"

  depends_on :macos

  def install
    libexec.install "lib"
    libexec.install "bin"
    libexec.install "share" if File.directory?("share")

    (bin/"spider").write <<~EOS
      #!/bin/bash
      export SPIDER_ROOT="#{libexec}"
      exec "#{libexec}/bin/spider" "$@"
    EOS

    chmod 0755, bin/"spider"
    chmod 0755, libexec/"bin/spider"
    chmod 0755, libexec/"lib/edge_reporter.pl" if (libexec/"lib/edge_reporter.pl").exist?

    notify = libexec/"share/Spider Cleaner.app/Contents/MacOS/spider-notify"
    chmod 0755, notify if notify.exist?
  end

  def caveats
    <<~EOS
      Spider Cleaner installed as `spider`.

        spider clean           # deep cleanup + notification
        spider clean --dry-run
        spider status
        spider --help
    EOS
  end

  test do
    assert_match "spider", shell_output("#{bin}/spider --version")
  end
end
