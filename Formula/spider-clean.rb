class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/spider-clean"
  url "https://github.com/anshpatelkb/spider-clean/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "fbbdb6dec9642c7e04a1698d7e3a1615cbece76ae70b4f5470bff0ad7680ae26"
  version "1.0.0"
  license "MIT"

  depends_on :macos

  def install
    libexec.install "lib"
    libexec.install "bin"
    libexec.install "share" if File.directory?("share")

    (bin/"spider-clean").write <<~EOS
      #!/bin/bash
      export SPIDER_ROOT="#{libexec}"
      exec "#{libexec}/bin/spider-clean" "$@"
    EOS

    chmod 0755, bin/"spider-clean"
    chmod 0755, libexec/"bin/spider-clean"
    chmod 0755, libexec/"lib/edge_reporter.pl" if (libexec/"lib/edge_reporter.pl").exist?

    notify = libexec/"share/Spider Cleaner.app/Contents/MacOS/spider-notify"
    chmod 0755, notify if notify.exist?
  end

  def caveats
    <<~EOS
      Installed as `spider-clean`.

        spider-clean clean
        spider-clean clean --dry-run
        spider-clean status
    EOS
  end

  test do
    assert_match "spider-clean", shell_output("#{bin}/spider-clean --version")
  end
end
