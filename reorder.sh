#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# K2 Gallery — Reorder Script
#
# Reorders js/photos.js according to the filenames listed in order.txt.
# Files not listed in order.txt are appended at the end (so you don't lose
# anything if you only list the ones you care about).
#
# Usage:
#   1. Create order.txt in this directory — one filename per line, e.g.:
#
#        IMG_5620.jpg
#        IMG_5625.jpg
#        IMG_5538.MOV
#        IMG_5682.MOV
#        ...
#
#      Use the base filename only (no path).
#      Lines starting with # are treated as comments and ignored.
#      Blank lines are ignored.
#
#   2. chmod +x reorder.sh   (first time only)
#   3. ./reorder.sh
#
# The script is non-destructive: it backs up photos.js before overwriting.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PHOTOS_JS="js/photos.js"
ORDER_FILE="order.txt"

# ── Sanity checks ──────────────────────────────────────────────────────────
if [ ! -f "$PHOTOS_JS" ]; then
  echo "Error: $PHOTOS_JS not found. Run ./setup.sh first."
  exit 1
fi

if [ ! -f "$ORDER_FILE" ]; then
  echo ""
  echo "  order.txt not found. Creating a sample one from the current order..."
  echo ""
  # Extract just the base filenames from current photos.js as a starter template
  grep '"src":' "$PHOTOS_JS" | \
    sed 's|.*display/||' | \
    sed 's|".*||' | \
    sed 's|^|# |' > "$ORDER_FILE"   # prefix with # so it's all comments initially
  # Append uncommented versions
  grep '"src":' "$PHOTOS_JS" | \
    sed 's|.*display/||' | \
    sed 's|".*||' >> "$ORDER_FILE"
  echo "  Created order.txt with all ${$(wc -l < "$ORDER_FILE" | tr -d ' ')} files in current order."
  echo "  Edit order.txt to set your preferred order, then re-run ./reorder.sh"
  echo ""
  exit 0
fi

# ── Parse photos.js into an associative map: filename → full js entry ───────
declare -A entry_map

current_entry=""
current_file=""

while IFS= read -r line; do
  trimmed="${line#"${line%%[![:space:]]*}"}"   # ltrim whitespace

  if [[ "$trimmed" == "{ id:"* ]]; then
    current_entry="$line"
    # Extract filename from src field:  "images/display/FILENAME"
    current_file="$(echo "$line" | sed 's|.*display/||' | sed 's|".*||')"
    entry_map["$current_file"]="$current_entry"
  fi
done < "$PHOTOS_JS"

total_entries="${#entry_map[@]}"
echo ""
echo "  K2 Gallery Reorder"
echo "  ─────────────────────────────────"
echo "  Loaded $total_entries entries from $PHOTOS_JS"

# ── Read desired order from order.txt ──────────────────────────────────────
ordered_files=()
while IFS= read -r line; do
  # Strip leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  # Skip blank lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue
  ordered_files+=("$line")
done < "$ORDER_FILE"

echo "  Found ${#ordered_files[@]} file(s) listed in $ORDER_FILE"

# ── Build new ordered array ────────────────────────────────────────────────
declare -A seen

new_entries=()
missing=()

# First: entries in the order specified by order.txt
for fname in "${ordered_files[@]}"; do
  if [[ -v "entry_map[$fname]" ]]; then
    new_entries+=("${entry_map[$fname]}")
    seen["$fname"]=1
  else
    missing+=("$fname")
  fi
done

# Then: any entries NOT listed in order.txt (appended at the end)
unlisted=()
for fname in "${!entry_map[@]}"; do
  if [[ ! -v "seen[$fname]" ]]; then
    unlisted+=("$fname")
  fi
done

# Sort unlisted alphabetically for deterministic output
IFS=$'\n' sorted_unlisted=($(sort <<<"${unlisted[*]}")); unset IFS

for fname in "${sorted_unlisted[@]}"; do
  new_entries+=("${entry_map[$fname]}")
done

# ── Report ─────────────────────────────────────────────────────────────────
if [ "${#missing[@]}" -gt 0 ]; then
  echo ""
  echo "  Warning: ${#missing[@]} filename(s) in order.txt not found in photos.js:"
  for m in "${missing[@]}"; do echo "    - $m"; done
fi

if [ "${#unlisted[@]}" -gt 0 ]; then
  echo "  ${#unlisted[@]} unlisted file(s) appended at the end."
fi

# ── Back up existing photos.js ─────────────────────────────────────────────
backup="${PHOTOS_JS}.bak"
cp "$PHOTOS_JS" "$backup"

# ── Write new photos.js ────────────────────────────────────────────────────
{
  echo "/**"
  echo " * K2 Gallery -- Photo & Video Data"
  echo " * Reordered by reorder.sh on $(date '+%Y-%m-%d %H:%M')"
  echo " *"
  echo " * Edit the  title  and  description  fields to add captions."
  echo " * Re-running reorder.sh preserves your edits; running setup.sh will overwrite."
  echo " */"
  echo ""
  echo "const PHOTOS = ["

  new_id=1
  for entry in "${new_entries[@]}"; do
    # Replace the id field with the new sequential id
    updated="$(echo "$entry" | sed "s/{ id: [0-9]*/{ id: $new_id/")"
    echo "$updated,"
    new_id=$((new_id + 1))
  done

  echo "];"
} > "$PHOTOS_JS"

echo ""
echo "  Done! $PHOTOS_JS reordered (${#new_entries[@]} entries)."
echo "  Backup saved to $backup"
echo ""
