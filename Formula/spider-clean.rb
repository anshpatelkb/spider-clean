class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/homebrew-spider-clean"
  version "1.3.1"
  license "MIT"

  # Commit archive (always exists on GitHub — no tag required)
  url "https://github.com/anshpatelkb/homebrew-spider-clean/archive/f197c2da330ec97fd9e46dcc54f02741f3b5f981.tar.gz"
  sha256 "7d954b031c602e9502d8eef4e27283d429ae082ba40fef4173d92ab5cc976de5"

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
    chmod 0755, libexec/"lib/postclean.py" if (libexec/"lib/postclean.py").exist?
  end

  def caveats
    <<~EOS
      spider-clean clean
      spider-clean clean --dry-run
      spider-clean status
    EOS
  end

  test do
    assert_match "spider-clean", shell_output("#{bin}/spider-clean --version")
  end
end
