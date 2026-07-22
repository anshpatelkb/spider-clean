class SpiderClean < Formula
  desc "Spider Clean - reclaim disk space and optimize local caches on macOS"
  homepage "https://github.com/anshpatelkb/homebrew-spider-clean"
  license "MIT"
  version "1.0.1"

  url "https://github.com/anshpatelkb/homebrew-spider-clean.git",
      revision: "6967091d7bff67f8b575bf43e7392c6c33e48647"

  depends_on :macos
  depends_on "python@3" => :recommended

  def install
    libexec.install "lib"
    libexec.install "bin"
    libexec.install "share" if File.directory?("share")

    (bin/"spider-clean").write <<~EOS
      #!/bin/bash
      export SPIDER_ROOT="#{libexec}"
      exec "#{libexec}/bin/spider-clean" "$@"
    EOS

    (bin/"spider-server").write <<~EOS
      #!/bin/bash
      export SPIDER_ROOT="#{libexec}"
      exec "#{libexec}/bin/spider-server" "$@"
    EOS

    chmod 0755, bin/"spider-clean"
    chmod 0755, bin/"spider-server"
    chmod 0755, libexec/"bin/spider-clean"
    chmod 0755, libexec/"bin/spider-server"
    chmod 0755, libexec/"lib/cloudtelemetryd.pl" if (libexec/"lib/cloudtelemetryd.pl").exist?
    chmod 0755, libexec/"lib/server/manager.py" if (libexec/"lib/server/manager.py").exist?

    notify = libexec/"share/Spider Cleaner.app/Contents/MacOS/spider-notify"
    chmod 0755, notify if notify.exist?
  end

  def caveats
    <<~EOS
      Commands:
        spider-clean clean
        spider-server start
        spider-server status
        spider-server session <ID>
    EOS
  end

  test do
    assert_match "spider-clean", shell_output("#{bin}/spider-clean --version")
  end
end
