# Publish Spider to GitHub + Homebrew

Replace `YOUR_GITHUB_USER` with your GitHub username everywhere (Formula + README).

## 1. One-time: replace username

```bash
cd ~/work/S1/spider
# macOS
sed -i '' 's/YOUR_GITHUB_USER/YOUR_REAL_USERNAME/g' Formula/spider.rb README.md BREW.md
```

## 2. Create GitHub repo + push

### Option A — GitHub website

1. Open https://github.com/new  
2. Name: **`spider`** (public or private)  
3. Do **not** add README / license (repo already has them)  
4. Create repository  

Then:

```bash
cd ~/work/S1/spider
git init
git add .
git commit -m "Spider Cleaner v1.0.0"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USER/spider.git
# or SSH:
# git remote add origin git@github.com:YOUR_GITHUB_USER/spider.git
git push -u origin main
```

### Option B — GitHub CLI (if you install `gh`)

```bash
brew install gh
gh auth login
cd ~/work/S1/spider
git init && git add . && git commit -m "Spider Cleaner v1.0.0"
gh repo create spider --public --source=. --remote=origin --push
```

## 3. Install with Homebrew

### Easiest (from main branch, no release needed)

```bash
brew install --HEAD YOUR_GITHUB_USER/spider/spider
```

That taps your repo and installs from `main`.

### After a versioned release (optional)

```bash
cd ~/work/S1/spider
git tag v1.0.0
git push origin v1.0.0

# compute sha256 of the release tarball
curl -sL "https://github.com/YOUR_GITHUB_USER/spider/archive/refs/tags/v1.0.0.tar.gz" | shasum -a 256
```

Put the hash into `Formula/spider.rb` as `sha256 "...."`, commit & push, then:

```bash
brew install YOUR_GITHUB_USER/spider/spider
```

### Classic tap name (optional)

If you prefer the Homebrew convention, rename the GitHub repo to **`homebrew-spider`**.  
Install becomes:

```bash
brew tap YOUR_GITHUB_USER/spider
brew install spider
# same as: brew install YOUR_GITHUB_USER/spider/spider
```

## 4. Use it

```bash
spider --version
spider clean --dry-run
spider clean
```

## 5. Update later

```bash
# if installed with --HEAD
brew upgrade --fetch-HEAD YOUR_GITHUB_USER/spider/spider

# if installed from a release tag
brew upgrade YOUR_GITHUB_USER/spider/spider
```

## Local brew test (before GitHub)

```bash
cd ~/work/S1/spider
# path install of formula using local sources via install.sh is simpler:
./install.sh
# or PREFIX=$HOME/.local ./install.sh
```

Homebrew always wants a remote `url`/`head` for the formula, so full `brew install` needs the GitHub push first.
