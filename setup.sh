#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# K2 Gallery — Setup Script
#
# Handles both photos AND videos:
#   Photos : converts HEIC/etc to JPEG, resizes for web, makes thumbnails
#   Videos : copies to display/, generates JPEG thumbnail via qlmanage
#
# 1. Creates web-optimised display copies in  images/display/  (<= 2000 px)
# 2. Creates grid thumbnails         in  images/thumbs/   (<= 500 px)
# 3. Writes js/photos.js  (with  type:"video"  for video entries)
#
# Your original files in  images/  are NEVER modified.
#
# Requirements: macOS (uses built-in sips + qlmanage -- no extra installs)
#
# Usage:
#   chmod +x setup.sh   (first time only)
#   ./setup.sh
#
# After running, edit js/photos.js to add captions, then open index.html.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ORIGINALS_DIR="images"
DISPLAY_DIR="images/display"
THUMBS_DIR="images/thumbs"
PHOTOS_JS="js/photos.js"

DISPLAY_MAX=2000
THUMB_MAX=500

# ── Sanity checks ──────────────────────────────────────────────────────────
if ! command -v sips &>/dev/null; then
  echo "sips not found. This script requires macOS."
  exit 1
fi

if [ ! -d "$ORIGINALS_DIR" ]; then
  echo "images/ directory not found. Create it and add your media files first."
  exit 1
fi

mkdir -p "$DISPLAY_DIR" "$THUMBS_DIR" js

# ── Collect files (images + videos, skip generated sub-folders) ────────────
shopt -s nullglob nocaseglob
all_imgs=("$ORIGINALS_DIR"/*.{jpg,jpeg,png,heic,heif,tiff,tif,bmp,webp})
all_vids=("$ORIGINALS_DIR"/*.{mp4,mov,m4v,avi,mkv,hevc,3gp})
shopt -u nullglob nocaseglob

originals=()
for f in "${all_imgs[@]}" "${all_vids[@]}"; do
  [[ "$f" == *"/display/"* || "$f" == *"/thumbs/"* ]] && continue
  originals+=("$f")
done

total="${#originals[@]}"

if [ "$total" -eq 0 ]; then
  echo ""
  echo "  No media files found in $ORIGINALS_DIR/"
  echo "  Supported images : jpg, jpeg, png, heic, heif, tiff, webp"
  echo "  Supported videos : mp4, mov, m4v, avi, mkv, hevc, 3gp"
  echo "  Drop your files there and re-run this script."
  echo ""
  exit 0
fi

echo ""
echo "  K2 Gallery Setup"
echo "  -------------------------------------------"
echo "  Found $total file(s) in $ORIGINALS_DIR/"
echo ""

# ── Helpers ────────────────────────────────────────────────────────────────

is_video() {
  local ext
  ext="$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in mp4|mov|m4v|avi|mkv|hevc|3gp) return 0 ;; esac
  return 1
}

make_title() {
  local name="$1"
  echo "$name" \
    | sed 's/[-_]/ /g' \
    | sed 's/[0-9]*$//' \
    | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ── Process each file ──────────────────────────────────────────────────────
count=0
vid_count=0
declare -a entries=()

for orig in "${originals[@]}"; do
  filename="$(basename "$orig")"
  name="${filename%.*}"
  count=$((count + 1))

  printf "  [%3d/%d]  %-42s" "$count" "$total" "$filename"

  title="$(make_title "$name")"

  if is_video "$orig"; then
    # ── VIDEO ───────────────────────────────────────────────────────────

    # Skip Live Photo companion clips (same basename as a sibling image file).
    # iPhone creates e.g. IMG_1234.HEIC + IMG_1234.MOV -- the MOV is a
    # 3-second clip, not a standalone video. We keep the HEIC, drop the MOV.
    is_live_companion=false
    for img_ext in jpg jpeg JPG JPEG heic HEIC heif HEIF png PNG tiff tif; do
      sibling="$ORIGINALS_DIR/${name}.${img_ext}"
      if [ -f "$sibling" ]; then
        is_live_companion=true
        break
      fi
    done
    if $is_live_companion; then
      count=$((count - 1))   # don't add to total count
      echo " skipped (Live Photo clip)"
      continue
    fi

    vid_count=$((vid_count + 1))
    [ -z "$title" ] && title="Video $vid_count"

    # Copy video to display/ as-is (no re-encoding)
    display_out="$DISPLAY_DIR/$filename"
    if [ ! -f "$display_out" ]; then
      cp "$orig" "$display_out"
    fi

    # Thumbnail via qlmanage (Quick Look -- no ffmpeg needed)
    thumb_out="$THUMBS_DIR/${name}.jpg"
    if [ ! -f "$thumb_out" ]; then
      qlmanage -t -s "$THUMB_MAX" -o "$THUMBS_DIR" "$orig" > /dev/null 2>&1
      # qlmanage names the output: <filename>.png  inside the output dir
      ql_png="$THUMBS_DIR/${filename}.png"
      if [ -f "$ql_png" ]; then
        sips -s format jpeg -s formatOptions 80 "$ql_png" --out "$thumb_out" > /dev/null 2>&1
        rm -f "$ql_png"
      else
        # Fallback: try <name>.png (qlmanage behaviour varies by macOS version)
        ql_png2="$THUMBS_DIR/${name}.png"
        if [ -f "$ql_png2" ]; then
          sips -s format jpeg -s formatOptions 80 "$ql_png2" --out "$thumb_out" > /dev/null 2>&1
          rm -f "$ql_png2"
        else
          # Last resort: blank placeholder (grid still shows; no broken icon)
          touch "$thumb_out"
        fi
      fi
    fi

    entries+=("  { id: $count, src: \"$display_out\", thumb: \"$thumb_out\", title: \"$title\", description: \"\", type: \"video\" }")

  else
    # ── IMAGE ───────────────────────────────────────────────────────────
    [ -z "$title" ] && title="Photo $count"

    out_name="${name}.jpg"
    display_out="$DISPLAY_DIR/$out_name"
    thumb_out="$THUMBS_DIR/$out_name"

    # Display copy: convert to JPEG + resize (handles HEIC, TIFF, etc.)
    sips -s format jpeg -s formatOptions 85 -Z "$DISPLAY_MAX" \
         "$orig" --out "$display_out" > /dev/null 2>&1

    # Thumbnail from display copy
    sips -s format jpeg -s formatOptions 80 -Z "$THUMB_MAX" \
         "$display_out" --out "$thumb_out" > /dev/null 2>&1

    entries+=("  { id: $count, src: \"$display_out\", thumb: \"$thumb_out\", title: \"$title\", description: \"\" }")
  fi

  echo " ok"
done

# ── Write js/photos.js ─────────────────────────────────────────────────────
{
  echo "/**"
  echo " * K2 Gallery -- Photo & Video Data"
  echo " * Auto-generated by setup.sh on $(date '+%Y-%m-%d %H:%M')"
  echo " *"
  echo " * Edit the  title  and  description  fields to add captions."
  echo " * Re-running setup.sh will overwrite this file."
  echo " */"
  echo ""
  echo "const PHOTOS = ["
  for entry in "${entries[@]}"; do
    echo "$entry,"
  done
  echo "];"
} > "$PHOTOS_JS"

# ── Summary ────────────────────────────────────────────────────────────────
display_size=$(du -sh "$DISPLAY_DIR" 2>/dev/null | cut -f1)
thumb_size=$(du -sh "$THUMBS_DIR"   2>/dev/null | cut -f1)
photo_count=$((count - vid_count))

echo ""
echo "  Done!"
echo ""
echo "  Originals       images/         (untouched)"
echo "  Display copies  $DISPLAY_DIR/  $display_size"
echo "  Thumbnails      $THUMBS_DIR/   $thumb_size"
echo "  Photo data      $PHOTOS_JS"
echo ""
echo "  $photo_count photo(s), $vid_count video(s)  --  $count total"
echo ""
echo "  Next steps:"
echo "  1. Edit js/photos.js to add captions (title / description fields)"
echo "  2. Open index.html in your browser to preview"
echo "  3. Commit to GitHub -- only commit images/display/ and images/thumbs/,"
echo "     not the originals in images/ (too large for GitHub)"
echo ""
echo "  .gitignore already excludes originals and keeps display/ + thumbs/"
echo ""

# Remind about GitHub file size limit for videos
if [ "$vid_count" -gt 0 ]; then
  echo "  NOTE: GitHub has a 100 MB per-file limit. Large videos may need"
  echo "  Git LFS (git lfs track 'images/display/*.mp4') or an external"
  echo "  host (YouTube/Vimeo embed). Check file sizes before pushing."
  echo ""
fi
