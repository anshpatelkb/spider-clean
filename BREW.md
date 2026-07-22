# Publish Spider Clean to GitHub + Homebrew

GitHub user: **anshpatelkb**  
Repo: **https://github.com/anshpatelkb/spider-clean**

## 1. Publish with GitHub Desktop

1. Open GitHub Desktop → this folder  
2. **Publish repository**  
3. Name: **`spider-clean`**  
4. Publish  

Or CLI after creating the empty repo on GitHub:

```bash
cd ~/work/S1/spider
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/anshpatelkb/spider-clean.git
git push -u origin main
```

## 2. Install with Homebrew

```bash
brew install --HEAD anshpatelkb/spider-clean/spider-clean
```

## 3. Use

```bash
spider-clean --version
spider-clean clean --dry-run
spider-clean clean
```

## 4. Update later

```bash
git push
brew upgrade --fetch-HEAD anshpatelkb/spider-clean/spider-clean
```
