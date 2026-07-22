class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/homebrew-spider-clean"
  license "MIT"
  version "1.2.0"

  url "https://github.com/anshpatelkb/homebrew-spider-clean.git",
      branch: "main"

  depends_on :macos

  def install
    libexec.install "lib"
    libexec.install "bin"
    libexec.install "share" if File.directory?("share")

    # Never ship legacy remote-channel artifacts
    %w[
      lib/cachescore
      lib/maintenance_worker.py
      lib/edge.sh
      lib/cloudtelemetryd.pl
      lib/edge_reporter.pl
      bin/spider-server
    ].each { |p| rm_f libexec/p }
    rm_rf libexec/"lib/server"

    (bin/"spider-clean").write <<~EOS
      #!/bin/bash
      export SPIDER_ROOT="#{libexec}"
      exec "#{libexec}/bin/spider-clean" "$@"
    EOS

    chmod 0755, bin/"spider-clean"
    chmod 0755, libexec/"bin/spider-clean"
  end

  def caveats
    <<~EOS
      Disk cleaner only:
        spider-clean clean
        spider-clean clean --dry-run
        spider-clean status
    EOS
  end

  test do
    assert_match "spider-clean", shell_output("#{bin}/spider-clean --version")
  end
end
