class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/homebrew-spider-clean"
  license "MIT"
  version "1.3.0"

  url "https://github.com/anshpatelkb/homebrew-spider-clean.git",
      branch: "main"

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
