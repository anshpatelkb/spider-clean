# Spider Clean — GitHub + Homebrew

Repo: **https://github.com/anshpatelkb/spider-clean**

## Install (no `--HEAD`)

```bash
brew install anshpatelkb/spider-clean/spider-clean
```

```bash
spider-clean --version
spider-clean clean --dry-run
spider-clean clean
```

## Push this release (if not already online)

In **GitHub Desktop**:

1. Open `~/work/S1/spider`
2. **Push origin** (main branch)
3. **Repository → Push** or ensure tag **v1.0.0** is pushed:
   - Menu: **Repository → Tags…** (or push all tags)
   - Or Terminal after Desktop auth:

```bash
cd ~/work/S1/spider
git push origin main
git push origin v1.0.0
```

## Update later (new version)

```bash
# after changes committed on main:
git tag v1.0.1
git push origin main v1.0.1
curl -sL https://github.com/anshpatelkb/spider-clean/archive/refs/tags/v1.0.1.tar.gz | shasum -a 256
# put new sha256 + url tag into Formula/spider-clean.rb, commit, push
brew upgrade anshpatelkb/spider-clean/spider-clean
```
