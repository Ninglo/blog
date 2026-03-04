#!/bin/bash
# Usage: ./publish.sh <path-to-article.md>
# Copies article + any referenced images to quartz/content/, then commits and pushes.
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
echo "✓ Published. Cloudflare Pages will deploy in ~1 min."
echo "  https://blog.jiujianian-dev-world.win"
