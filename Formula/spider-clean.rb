class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/homebrew-spider-clean"
  license "MIT"
  version "1.0.0"

  # Git checkout (no tarball sha256). Repo MUST be named homebrew-spider-clean
  # so this one-liner works:
  #   brew install anshpatelkb/spider-clean/spider-clean
  url "https://github.com/anshpatelkb/homebrew-spider-clean.git",
      revision: "6967091d7bff67f8b575bf43e7392c6c33e48647"

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
