# Spider Clean

Lightweight **Mac system cleaner** for the terminal — reclaim disk space from caches, developer tools, browsers, logs, installers, and Trash.

```text
spider-clean clean
```

## Install (Homebrew)

Repo name is **`spider-clean`** (not `homebrew-spider-clean`), so you must pass the full GitHub URL when tapping:

```bash
brew tap anshpatelkb/spider-clean https://github.com/anshpatelkb/spider-clean
brew install spider-clean
```

```bash
spider-clean --version
spider-clean clean --dry-run
spider-clean clean
```

### Update

```bash
brew update
brew upgrade spider-clean
```

### Local (no Homebrew)

```bash
chmod +x install.sh bin/spider-clean lib/edge_reporter.pl
./install.sh
# PREFIX=$HOME/.local ./install.sh
```

## Usage

```bash
spider-clean                 # interactive menu
spider-clean clean           # deep cleanup + desktop notification
spider-clean clean --dry-run # preview only
spider-clean status          # disk snapshot
spider-clean --version
spider-clean --help
```

## What gets cleaned

| Category | Examples |
|----------|----------|
| App caches | Safari helpers, system service caches |
| Browsers | Chrome, Firefox, Brave, Edge, Dia |
| Developer | Homebrew, npm, Yarn, pip, Xcode DerivedData, simulators, Gradle |
| Messaging | Slack, Discord, Spotify, Zoom, VS Code caches |
| Logs | User logs, diagnostic reports |
| Installers | Old `.dmg` / `.pkg` in Downloads & Desktop (14+ days, 10MB+) |
| Trash | Emptied via Finder |

## License

MIT
