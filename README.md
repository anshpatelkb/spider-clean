# Spider Clean

Lightweight **Mac system cleaner** for the terminal — reclaim disk space from caches, developer tools, browsers, logs, installers, and Trash.

```text
spider-clean clean
```

After cleanup you get a **macOS notification** with how much space was reclaimed and free space remaining.

## Install

### Homebrew

Repo: **https://github.com/anshpatelkb/spider-clean**

```bash
brew install anshpatelkb/spider-clean/spider-clean
```

No `--HEAD` needed (uses release **v1.0.0**).  
Full guide: **[BREW.md](BREW.md)**

### Local (no GitHub)

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

Protected paths (home, Documents, System, etc.) are never wiped wholesale.

## Notification

On completion, Spider shows a macOS notification:

- **Title:** Spider Cleaner  
- **Body:** Cleaned *X* · Free space now: *Y*  

## License

MIT
