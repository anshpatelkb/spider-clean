class Spider < Formula
  desc "Spider Cleaner - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/spider"
  license "MIT"
  version "1.0.0"

  # Install from main after the repo is public on GitHub:
  #   brew install --HEAD anshpatelkb/spider/spider
  head "https://github.com/anshpatelkb/spider.git", branch: "main"

  # Temporary: also allow installing latest main tarball once repo exists
  url "https://github.com/anshpatelkb/spider/archive/refs/heads/main.tar.gz"
  # sha256 is omitted intentionally for main-branch snapshots; prefer --HEAD

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

        spider clean
        spider clean --dry-run
        spider status
    EOS
  end

  test do
    assert_match "spider", shell_output("#{bin}/spider --version")
  end
end
