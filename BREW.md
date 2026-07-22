# Publish Spider to GitHub + Homebrew

GitHub user: **anshpatelkb**  
Repo: **https://github.com/anshpatelkb/spider**

## 1. Create GitHub repo + push

1. Open https://github.com/new  
2. Name: **`spider`** (public or private)  
3. Do **not** add README / license (repo already has them)  
4. Create repository  

Then:

```bash
cd ~/work/S1/spider
git remote add origin git@github.com:anshpatelkb/spider.git
# or HTTPS:
# git remote add origin https://github.com/anshpatelkb/spider.git
git push -u origin main
```

## 2. Install with Homebrew

```bash
brew install --HEAD anshpatelkb/spider/spider
```

That taps your repo and installs from `main`.

### After a versioned release (optional)

```bash
cd ~/work/S1/spider
git tag v1.0.0
git push origin v1.0.0
curl -sL "https://github.com/anshpatelkb/spider/archive/refs/tags/v1.0.0.tar.gz" | shasum -a 256
```

Put the hash into `Formula/spider.rb` as `sha256 "...."`, commit & push, then:

```bash
brew install anshpatelkb/spider/spider
```

## 3. Use it

```bash
spider --version
spider clean --dry-run
spider clean
```

## 4. Update later

```bash
git push
brew upgrade --fetch-HEAD anshpatelkb/spider/spider
```
