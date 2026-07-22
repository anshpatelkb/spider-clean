# Spider Clean

Lightweight **Mac system cleaner** for the terminal.

```text
spider-clean clean
```

## Install (one command)

GitHub repo must be named **`homebrew-spider-clean`** (Homebrew rule).

```bash
brew install anshpatelkb/spider-clean/spider-clean
```

That’s it — no separate `brew tap` step.

```bash
spider-clean --version
spider-clean clean --dry-run
spider-clean clean
```

### First-time setup of this repo on GitHub

1. If the repo is still named `spider-clean`, rename it:
   - GitHub → **Settings** → **General** → **Repository name** → `homebrew-spider-clean` → **Rename**
2. Push this project (GitHub Desktop → **Push origin**).

### Local install (no Homebrew)

```bash
./install.sh
```

## Usage

```bash
spider-clean                 # menu
spider-clean clean           # cleanup + notification
spider-clean clean --dry-run
spider-clean status
spider-clean --help
```

## License

MIT
