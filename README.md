# Slang NPR — toon-shading

## First download
```bash
git clone --branch toon-shading https://github.com/Enhui000/balboa_slang_practice.git
cd balboa_slang_practice
uv sync
uv run python npr_demo.py --style toon
```

## Switch versions
Run one pair at a time, from the repository folder. Commit your changes before switching.
```bash
git fetch origin
git switch branch1
uv run python npr_demo.py --style combined
```
```bash
git switch branch2
uv run python npr_demo.py --style combined
```
```bash
git switch toon-shading
uv run python npr_demo.py --style toon
```
```bash
git switch lines
uv run python npr_demo.py --style lines
```

## Download latest changes
```bash
git pull --ff-only
uv sync
uv run python npr_demo.py --style toon
```

## Upload your changes on the current branch
```bash
git branch --show-current
git status
git add -u
git commit -m "Update renderer"
git push -u origin HEAD
```
For a new file, run `git add path/to/file` before committing.

## Export a picture
```bash
uv run python npr_demo.py --style toon --output outputs/toon-shading.png
```

Requires Git and uv. See [README_NPR.md](README_NPR.md) for rendering details, controls, attribution, and known limits. macOS Metal and the interactive window still require verification on your machine.
