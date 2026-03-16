#!/bin/bash
# Usage: ./publish.sh <path-to-article.md>
# Publish flow has two content steps:
# 1) Normalize the article into `content/` with `title`/`date` frontmatter
# 2) Rebuild `content/index.md` sorted by date descending
#
# After content is committed and pushed, the GitHub-connected site auto-deploys.
# Set `PUBLISH_SKIP_GIT=1` to validate content changes locally without commit/push.
# Set `PUBLISH_DATE=YYYY-MM-DD` to override the default publish date.
# Example: ./publish.sh ~/my_docs/AI/新文章.md

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENT_DIR="$ROOT_DIR/content"
INDEX_FILE="$CONTENT_DIR/index.md"
ARTICLE="${1:-}"
PUBLISH_DATE="${PUBLISH_DATE:-$(date +%F)}"
SKIP_GIT="${PUBLISH_SKIP_GIT:-0}"

if [ -z "$ARTICLE" ]; then
  echo "Usage: ./publish.sh <path-to-article.md>"
  exit 1
fi

if [ ! -f "$ARTICLE" ]; then
  echo "Error: file not found: $ARTICLE"
  exit 1
fi

ARTICLE_DIR="$(dirname "$ARTICLE")"
TMP_BODY="$(mktemp)"
TMP_ITEMS="$(mktemp)"
TMP_SORTED="$(mktemp)"

cleanup() {
  rm -f "$TMP_BODY" "$TMP_ITEMS" "$TMP_SORTED"
}

trap cleanup EXIT

frontmatter_value() {
  local key="$1"
  local file="$2"

  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ": ") == 1 {
      print substr($0, length(key) + 3)
      exit
    }
  ' "$file"
}

has_frontmatter() {
  [ "$(head -n 1 "$1")" = "---" ]
}

strip_frontmatter() {
  local file="$1"

  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    !in_frontmatter { print }
  ' "$file"
}

sanitize_filename() {
  printf '%s' "$1" | tr '/' '／'
}

extract_title() {
  local title

  title="$(frontmatter_value title "$ARTICLE")"
  if [ -z "$title" ]; then
    title="$(sed -n 's/^# //p' "$ARTICLE" | head -n 1)"
  fi
  if [ -z "$title" ]; then
    title="$(basename "$ARTICLE" .md)"
  fi

  printf '%s' "$title"
}

extract_date() {
  local date_value

  date_value="$(frontmatter_value date "$ARTICLE")"
  if [ -z "$date_value" ]; then
    date_value="$PUBLISH_DATE"
  fi

  printf '%s' "$date_value"
}

build_index() {
  : > "$TMP_ITEMS"

  for file in "$CONTENT_DIR"/*.md; do
    local stem title date_value

    if [ "$(basename "$file")" = "index.md" ]; then
      continue
    fi

    stem="$(basename "$file" .md)"
    title="$(frontmatter_value title "$file")"
    date_value="$(frontmatter_value date "$file")"

    if [ -z "$date_value" ]; then
      echo "Error: missing date in $(basename "$file")" >&2
      exit 1
    fi

    if [ -z "$title" ]; then
      title="$stem"
    fi

    printf '%s\t%s\t%s\n' "$date_value" "$stem" "$title" >> "$TMP_ITEMS"
  done

  sort -r "$TMP_ITEMS" > "$TMP_SORTED"

  {
    printf -- '---\n'
    printf 'title: jiujianian\n'
    printf -- '---\n\n'
    printf '## 文章\n\n'

    while IFS=$'\t' read -r date_value stem title; do
      if [ "$title" = "$stem" ]; then
        printf -- '- [[%s]] `%s`\n' "$stem" "$date_value"
      else
        printf -- '- [[%s|%s]] `%s`\n' "$stem" "$title" "$date_value"
      fi
    done < "$TMP_SORTED"
  } > "$INDEX_FILE"
}

TITLE="$(extract_title)"
DATE_VALUE="$(extract_date)"
TARGET_STEM="$(sanitize_filename "$TITLE")"
TARGET_ARTICLE="$CONTENT_DIR/$TARGET_STEM.md"

if has_frontmatter "$ARTICLE"; then
  strip_frontmatter "$ARTICLE" > "$TMP_BODY"
else
  if [ "$(head -n 1 "$ARTICLE")" = "# $TITLE" ]; then
    tail -n +2 "$ARTICLE" | sed '1{/^[[:space:]]*$/d;}' > "$TMP_BODY"
  else
    cat "$ARTICLE" > "$TMP_BODY"
  fi
fi

{
  printf -- '---\n'
  printf 'title: %s\n' "$TITLE"
  printf 'date: %s\n' "$DATE_VALUE"
  printf -- '---\n\n'
  cat "$TMP_BODY"
} > "$TARGET_ARTICLE"

echo "✓ Wrote article: $(basename "$TARGET_ARTICLE")"

# Copy any referenced images (![...](filename.ext) — relative paths only)
while read -r img; do
  if [ -z "$img" ]; then
    continue
  fi

  # Skip URLs
  if [[ "$img" == http* ]]; then continue; fi
  IMG_PATH="$ARTICLE_DIR/$img"
  if [ -f "$IMG_PATH" ]; then
    cp "$IMG_PATH" "$CONTENT_DIR/"
    echo "✓ Copied image: $img"
  else
    echo "⚠ Image not found: $img"
  fi
done < <(grep -oE '!\[[^]]*\]\(([^)]+)\)' "$ARTICLE" | grep -oE '\([^)]+\)' | tr -d '()' || true)

build_index
echo "✓ Rebuilt: $(basename "$INDEX_FILE")"

if [ "$SKIP_GIT" = "1" ]; then
  echo "✓ Skipped git commit/push (PUBLISH_SKIP_GIT=1)"
  exit 0
fi

cd "$ROOT_DIR"
git add content/

if git diff --cached --quiet; then
  echo "✓ No content changes to commit"
  exit 0
fi

git commit -m "publish: $TITLE"
git push

echo ""
echo "✓ Published. Git push will trigger the site's auto-deploy."
echo "  https://blog.jiujianian.dev"
