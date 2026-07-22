# Spider Cleaner

Lightweight **Mac system cleaner** for the terminal — reclaim disk space from caches, developer tools, browsers, logs, installers, and Trash.

```text
spider clean
```

After cleanup you get a **macOS notification** with how much space was reclaimed and free space remaining.

## Install

### Homebrew (after you push this repo to GitHub)

1. Push this repo to **https://github.com/anshpatelkb/spider** (see [BREW.md](BREW.md)).  
2. Install:

```bash
brew install --HEAD anshpatelkb/spider/spider
```

Full publish guide: **[BREW.md](BREW.md)**

### Local (no GitHub)

```bash
chmod +x install.sh bin/spider lib/edge_reporter.pl
./install.sh                    # → /usr/local/bin/spider
# PREFIX=$HOME/.local ./install.sh
```

## Usage

```bash
spider                 # interactive menu
spider clean           # deep cleanup + desktop notification
spider clean --dry-run # preview only
spider status          # disk snapshot
spider --version
spider --help
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
- Icon from the bundled Spider Cleaner assets  

## License

MIT
