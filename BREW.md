# One-command Homebrew install

## Why a special repo name?

```bash
brew install anshpatelkb/spider-clean/spider-clean
```

Homebrew always clones:

```text
https://github.com/anshpatelkb/homebrew-spider-clean
```

So the GitHub repository **must** be named:

```text
homebrew-spider-clean
```

not `spider-clean`.

## Setup (once)

1. Open https://github.com/anshpatelkb/spider-clean/settings  
2. **Repository name** → rename to **`homebrew-spider-clean`** → **Rename**  
3. In GitHub Desktop, push this project (remote becomes `homebrew-spider-clean` after rename; Desktop usually follows redirects)

Or set remote after rename:

```bash
cd ~/work/S1/spider
git remote set-url origin https://github.com/anshpatelkb/homebrew-spider-clean.git
git push -u origin main
```

## Install on any Mac (one command)

```bash
brew install anshpatelkb/spider-clean/spider-clean
```

If brew asks to trust the tap:

```bash
brew trust anshpatelkb/spider-clean
brew install anshpatelkb/spider-clean/spider-clean
```

## Upgrade

```bash
brew upgrade anshpatelkb/spider-clean/spider-clean
```
