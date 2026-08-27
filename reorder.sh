#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# K2 Gallery — Reorder Script
#
# Reorders js/photos.js according to:
#   1. order.txt  — pinned items placed at the beginning of the gallery
#   2. Chronological / unlisted items in the middle
#   3. bottom.txt — pinned items placed at the end of the gallery
#
# Usage:
#   1. Edit order.txt to pin items to the top (one filename per line)
#   2. Edit bottom.txt to pin items to the bottom (one filename per line)
#   3. ./reorder.sh
#
# The script is non-destructive: it backs up photos.js before overwriting.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PHOTOS_JS="js/photos.js"
ORDER_FILE="order.txt"
BOTTOM_FILE="bottom.txt"

# ── Sanity checks ──────────────────────────────────────────────────────────
if [ ! -f "$PHOTOS_JS" ]; then
  echo "Error: $PHOTOS_JS not found. Run ./setup.sh first."
  exit 1
fi

if [ ! -f "$ORDER_FILE" ]; then
  echo ""
  echo "  order.txt not found. Creating a starter template..."
  echo "# Pinned pictures at the beginning of the gallery" > "$ORDER_FILE"
fi

if [ ! -f "$BOTTOM_FILE" ]; then
  echo ""
  echo "  bottom.txt not found. Creating a starter template..."
  echo "# Pinned pictures and videos at the end of the gallery" > "$BOTTOM_FILE"
fi

# Run python reorder engine for cross-platform reliability
python3 - << 'EOF'
import os
import re
import shutil
from datetime import datetime

photos_file = "js/photos.js"
order_file = "order.txt"
bottom_file = "bottom.txt"
backup_file = "js/photos.js.bak"

if not os.path.exists(photos_file):
    print(f"Error: {photos_file} not found.")
    exit(1)

with open(photos_file, "r") as f:
    photos_content = f.read()

entries = []
for line in photos_content.splitlines():
    line_s = line.strip()
    if line_s.startswith("{ id:") or line_s.startswith("{id:"):
        m = re.search(r'src:\s*"images/display/([^"]+)"', line)
        if m:
            fname = m.group(1)
            line_clean = line.rstrip(", \t")
            entries.append((fname, line_clean))

total_entries = len(entries)
print("")
print("  K2 Gallery Reorder")
print("  ─────────────────────────────────")
print(f"  Loaded {total_entries} entries from {photos_file}")

def read_list_file(filepath):
    lines = []
    if os.path.exists(filepath):
        with open(filepath, "r") as f:
            for l in f:
                l = l.strip()
                if l and not l.startswith("#"):
                    lines.append(l)
    return lines

top_lines = read_list_file(order_file)
bottom_lines = read_list_file(bottom_file)

print(f"  Top pinned (from {order_file}): {len(top_lines)} file(s)")
print(f"  Bottom pinned (from {bottom_file}): {len(bottom_lines)} file(s)")

entry_map = {fname: raw for fname, raw in entries}
entry_map_lower = {fname.lower(): (fname, raw) for fname, raw in entries}

def match_target(target):
    if target in entry_map:
        return (target, entry_map[target])
    if target.lower() in entry_map_lower:
        return entry_map_lower[target.lower()]
    for ext in [".jpg", ".MOV", ".mov", ".mp4", ".png", ".HEIC", ".heic"]:
        t_ext = (target + ext).lower()
        if t_ext in entry_map_lower:
            return entry_map_lower[t_ext]
    return None

seen = set()
missing = []

# 1. Top entries
top_entries = []
for target in top_lines:
    matched = match_target(target)
    if matched:
        fname, raw = matched
        if fname not in seen:
            top_entries.append((fname, raw))
            seen.add(fname)
    else:
        missing.append((order_file, target))

# 2. Bottom entries
bottom_entries = []
bottom_seen = set()
for target in bottom_lines:
    matched = match_target(target)
    if matched:
        fname, raw = matched
        if fname not in seen and fname not in bottom_seen:
            bottom_entries.append((fname, raw))
            bottom_seen.add(fname)
    else:
        missing.append((bottom_file, target))

if missing:
    print(f"\n  Warning: {len(missing)} filename(s) not found in {photos_file}:")
    for src_f, m in missing:
        print(f"    - [{src_f}] {m}")

# 3. Middle entries (unlisted in order.txt or bottom.txt)
middle_entries = []
for fname, raw in entries:
    if fname not in seen and fname not in bottom_seen:
        middle_entries.append((fname, raw))

print(f"  Middle items (chronological): {len(middle_entries)} file(s)")

ordered_entries = top_entries + middle_entries + bottom_entries

# Backup
shutil.copyfile(photos_file, backup_file)

# Write updated photos.js
now_str = datetime.now().strftime("%Y-%m-%d %H:%M")
header = f"""/**
 * K2 Gallery -- Photo & Video Data
 * Reordered by reorder.sh on {now_str}
 *
 * Edit the  title  and  description  fields to add captions.
 * Re-running reorder.sh preserves your edits; running setup.sh will overwrite.
 */

const PHOTOS = [
"""

with open(photos_file, "w") as f:
    f.write(header)
    for new_id, (fname, raw) in enumerate(ordered_entries, 1):
        updated_line = re.sub(r"\{\s*id:\s*\d+", f"{{ id: {new_id}", raw)
        f.write(f"  {updated_line.strip()},\n")
    f.write("];\n")

print(f"\n  Done! {photos_file} reordered ({len(ordered_entries)} entries total).")
print(f"  Backup saved to {backup_file}\n")
EOF
