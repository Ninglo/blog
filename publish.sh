#!/bin/bash
# Usage: ./publish.sh <path-to-article.md>
# Publish flow has two content steps:
# 1) Copy the article + any referenced local images into `content/`
# 2) Update `content/index.md` and place the newest article at the top
#
# After content is committed and pushed, the GitHub-connected site auto-deploys.
# Example: ./publish.sh ~/my_docs/AI/新文章.md

set -e

CONTENT_DIR="$(dirname "$0")/content"
ARTICLE="$1"

if [ -z "$ARTICLE" ]; then
  echo "Usage: ./publish.sh <path-to-article.md>"
  exit 1
fi

if [ ! -f "$ARTICLE" ]; then
  echo "Error: file not found: $ARTICLE"
  exit 1
fi

ARTICLE_DIR="$(dirname "$ARTICLE")"
ARTICLE_NAME="$(basename "$ARTICLE")"

# Copy the article
cp "$ARTICLE" "$CONTENT_DIR/"
echo "✓ Copied: $ARTICLE_NAME"

# Copy any referenced images (![...](filename.ext) — relative paths only)
grep -oE '!\[[^]]*\]\(([^)]+)\)' "$ARTICLE" | grep -oE '\([^)]+\)' | tr -d '()' | while read -r img; do
  # Skip URLs
  if [[ "$img" == http* ]]; then continue; fi
  IMG_PATH="$ARTICLE_DIR/$img"
  if [ -f "$IMG_PATH" ]; then
    cp "$IMG_PATH" "$CONTENT_DIR/"
    echo "✓ Copied image: $img"
  else
    echo "⚠ Image not found: $img"
  fi
done

# Commit and push
cd "$(dirname "$0")"
git add content/
git commit -m "publish: $ARTICLE_NAME"
git push

echo ""
echo "✓ Published. Git push will trigger the site's auto-deploy."
echo "  https://blog.jiujianian-dev-world.win"
