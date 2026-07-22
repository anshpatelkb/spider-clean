# Homebrew install (spider-clean)

## Why the short command failed

```text
brew install anshpatelkb/spider-clean/spider-clean
```

Homebrew rewrites that tap to:

```text
https://github.com/anshpatelkb/homebrew-spider-clean
```

Your repo is named **`spider-clean`**, not **`homebrew-spider-clean`**, so clone fails.

## Correct install (use this)

```bash
# 1) clear a broken partial tap if present
brew untap anshpatelkb/spider-clean 2>/dev/null || true

# 2) tap with the real GitHub URL
brew tap anshpatelkb/spider-clean https://github.com/anshpatelkb/spider-clean

# 3) install (no --HEAD)
brew install spider-clean
```

## Use

```bash
spider-clean --version
spider-clean clean --dry-run
spider-clean clean
```

## Optional: short tap name forever

On GitHub → repo **Settings → General → Repository name**  
rename `spider-clean` → **`homebrew-spider-clean`**.

Then this works without a custom URL:

```bash
brew install anshpatelkb/spider-clean/spider-clean
```
