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

# ── Helpers ────────────────────────────────────────────────────────────────

is_video() {
  local ext
  ext="$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in mp4|mov|m4v|avi|mkv|hevc|3gp) return 0 ;; esac
  return 1
}


get_creation_date() {
  local f="$1"
  local raw=""

  # 1. Spotlight metadata (macOS built-in - extracts original EXIF / QuickTime creation date in UTC)
  if command -v mdls &>/dev/null; then
    raw="$(mdls -name kMDItemContentCreationDate -raw "$f" 2>/dev/null || true)"
    if [ -n "$raw" ] && [ "$raw" != "(null)" ]; then
      # Convert UTC timestamp to Pakistan Standard Time (PKT, UTC+5)
      TZ="Asia/Karachi" date -jf "%Y-%m-%d %H:%M:%S %z" "$raw" "+%Y-%m-%d %H:%M:%S" 2>/dev/null && return 0
    fi
  fi

  # 2. ffprobe fallback for videos (creation_time is in UTC)
  if command -v ffprobe &>/dev/null && is_video "$f"; then
    raw="$(ffprobe -v quiet -print_format json -show_entries format_tags=creation_time "$f" 2>/dev/null | grep -o '"creation_time": "[^"]*"' | cut -d'"' -f4 | cut -d'.' -f1 | tr 'T' ' ' || true)"
    if [ -n "$raw" ]; then
      TZ="Asia/Karachi" date -jf "%Y-%m-%d %H:%M:%S %z" "$raw +0000" "+%Y-%m-%d %H:%M:%S" 2>/dev/null && return 0
    fi
  fi

  # 3. sips fallback for images
  if command -v sips &>/dev/null && ! is_video "$f"; then
    raw="$(sips -g creation "$f" 2>/dev/null | awk '/creation:/ {print $2, $3}' | tr ':' '-' || true)"
    if [ -n "$raw" ] && [ "$raw" != "<nil>" ]; then
      echo "$raw"
      return 0
    fi
  fi

  # 4. Filesystem stat fallback (macOS)
  stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$f" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S"
}

# ── Filter & Sort Chronologically ──────────────────────────────────────────
file_date_pairs=()
for orig in "${originals[@]}"; do
  filename="$(basename "$orig")"
  name="${filename%.*}"

  # Skip Live Photo companion clips (same basename as a sibling image file).
  if is_video "$orig"; then
    is_live_companion=false
    for img_ext in jpg jpeg JPG JPEG heic HEIC heif HEIF png PNG tiff tif; do
      sibling="$ORIGINALS_DIR/${name}.${img_ext}"
      if [ -f "$sibling" ]; then
        is_live_companion=true
        break
      fi
    done
    if $is_live_companion; then
      continue
    fi
  fi

  date_val="$(get_creation_date "$orig")"
  file_date_pairs+=("${date_val}|${orig}")
done

# Sort chronologically by creation date, then filename for deterministic order
sorted_media=()
while IFS= read -r line; do
  [[ -n "$line" ]] && sorted_media+=("$line")
done < <(printf "%s\n" "${file_date_pairs[@]}" | sort -t"|" -k1,1 -k2,2)

total="${#sorted_media[@]}"

echo ""
echo "  K2 Gallery Setup"
echo "  -------------------------------------------"
echo "  Found $total media file(s) in $ORIGINALS_DIR/ (sorted chronologically)"
echo ""

# ── Process each file ──────────────────────────────────────────────────────
count=0
vid_count=0
declare -a entries=()

for item in "${sorted_media[@]}"; do
  creation_date="${item%%|*}"
  orig="${item#*|}"
  filename="$(basename "$orig")"
  name="${filename%.*}"
  count=$((count + 1))

  printf "  [%3d/%d]  %-42s (%s)" "$count" "$total" "$filename" "$creation_date"

  if is_video "$orig"; then
    # ── VIDEO ───────────────────────────────────────────────────────────
    vid_count=$((vid_count + 1))
    title="$filename"

    # Display copy: re-encode with ffmpeg to keep file size web/GitHub-friendly
    # (falls back to a plain copy if ffmpeg isn't installed)
    display_out="$DISPLAY_DIR/$filename"
    if [ ! -f "$display_out" ]; then
      if command -v ffmpeg &>/dev/null && command -v ffprobe &>/dev/null; then
        fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
              -of default=noprint_wrappers=1:nokey=1 "$orig" | awk -F'/' '{ if ($2==0) print 0; else print $1/$2 }')
        rflag=()
        if awk "BEGIN{exit !($fps > 30)}" 2>/dev/null; then
          rflag=(-r 30)
        fi
        ffmpeg -nostdin -y -i "$orig" \
          -vf "scale='if(gt(iw,ih),min(iw,1920),-2)':'if(gt(iw,ih),-2,min(ih,1920))'" \
          "${rflag[@]+"${rflag[@]}"}" -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p \
          -c:a aac -b:a 128k -movflags +faststart \
          "$display_out" -loglevel error
      else
        cp "$orig" "$display_out"
      fi
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

    entries+=("  { id: $count, src: \"$display_out\", thumb: \"$thumb_out\", title: \"$title\", description: \"\", date: \"$creation_date\", type: \"video\" }")

  else
    # ── IMAGE ───────────────────────────────────────────────────────────
    out_name="${name}.jpg"
    title="$out_name"
    display_out="$DISPLAY_DIR/$out_name"
    thumb_out="$THUMBS_DIR/$out_name"

    # Display copy: convert to JPEG + resize (handles HEIC, TIFF, etc.)
    if [ ! -f "$display_out" ]; then
      sips -s format jpeg -s formatOptions 85 -Z "$DISPLAY_MAX" \
           "$orig" --out "$display_out" > /dev/null 2>&1
    fi

    # Thumbnail from display copy
    if [ ! -f "$thumb_out" ]; then
      sips -s format jpeg -s formatOptions 80 -Z "$THUMB_MAX" \
           "$display_out" --out "$thumb_out" > /dev/null 2>&1
    fi

    entries+=("  { id: $count, src: \"$display_out\", thumb: \"$thumb_out\", title: \"$title\", description: \"\", date: \"$creation_date\" }")
  fi

  echo " ok"
done

# ── Write js/photos.js ─────────────────────────────────────────────────────
{
  echo "/**"
  echo " * K2 Gallery -- Photo & Video Data"
  echo " * Auto-generated by setup.sh on $(date '+%Y-%m-%d %H:%M')"
  echo " * Ordered chronologically by original metadata creation date"
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

# ── Apply custom order if order.txt or bottom.txt exist ───────────────────
if [ -f "./reorder.sh" ] && { [ -f "order.txt" ] || [ -f "bottom.txt" ]; }; then
  chmod +x ./reorder.sh
  ./reorder.sh > /dev/null 2>&1 || true
fi

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
