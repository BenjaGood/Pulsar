#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="${1:-/Volumes/Benjamin SSD/Aetherial/Aetherial Main/Pulsar_2logo.png}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGICK_BIN="${MAGICK:-$(command -v magick || true)}"
BACKGROUND_COLOR="${PULSAR_ICON_BACKGROUND:-#FFFFFF}"

APP_ICON_SETS=(
  "$ROOT_DIR/Pulsar/Assets.xcassets/AppIcon.appiconset"
  "$ROOT_DIR/Pulsar Watch App Watch App/Assets.xcassets/AppIcon.appiconset"
)

if [[ -z "$MAGICK_BIN" ]]; then
  echo "error: ImageMagick 'magick' was not found. Install it with Homebrew or set MAGICK=/path/to/magick." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "error: source image not found: $SOURCE_IMAGE" >&2
  exit 1
fi

for icon_set in "${APP_ICON_SETS[@]}"; do
  if [[ ! -d "$icon_set" ]]; then
    echo "error: AppIcon set not found: $icon_set" >&2
    exit 1
  fi
  if [[ ! -f "$icon_set/Contents.json" ]]; then
    echo "error: Contents.json not found in: $icon_set" >&2
    exit 1
  fi
done

manifest_file="$(mktemp)"
trap 'rm -f "$manifest_file"' EXIT

python3 - "$manifest_file" "${APP_ICON_SETS[@]}" <<'PY'
import json
import math
import pathlib
import re
import sys

manifest_path = pathlib.Path(sys.argv[1])
icon_sets = [pathlib.Path(path) for path in sys.argv[2:]]
manifest_lines = []

def pixel_size(image):
    width_text = image["size"].split("x", 1)[0]
    scale_text = image.get("scale", "1x").removesuffix("x")
    return int(round(float(width_text) * float(scale_text)))

def safe_part(value):
    return re.sub(r"[^A-Za-z0-9.]+", "_", value).strip("_")

def generated_filename(image, pixels, existing_names):
    idiom = image.get("idiom", "icon")
    if idiom in {"watch", "watch-marketing"}:
        base = f"watch_{pixels}.png"
    else:
        size = safe_part(image["size"])
        scale = safe_part(image.get("scale", "1x"))
        base = f"icon_{size}@{scale}.png"

    if base not in existing_names:
        return base

    role = safe_part(image.get("role", ""))
    subtype = safe_part(image.get("subtype", ""))
    suffix = "_".join(part for part in [role, subtype] if part)
    if suffix:
        candidate = base.replace(".png", f"_{suffix}.png")
        if candidate not in existing_names:
            return candidate

    index = 2
    while True:
        candidate = base.replace(".png", f"_{index}.png")
        if candidate not in existing_names:
            return candidate
        index += 1

for icon_set in icon_sets:
    contents_path = icon_set / "Contents.json"
    data = json.loads(contents_path.read_text())
    images = data.get("images", [])
    existing_names = {image["filename"] for image in images if image.get("filename")}

    for image in images:
        pixels = pixel_size(image)
        filename = image.get("filename")
        if not filename:
            filename = generated_filename(image, pixels, existing_names)
            image["filename"] = filename
            existing_names.add(filename)
        manifest_lines.append(f"{icon_set}\t{filename}\t{pixels}")

    contents_path.write_text(json.dumps(data, indent=2) + "\n")

manifest_path.write_text("\n".join(manifest_lines) + "\n")
PY

for icon_set in "${APP_ICON_SETS[@]}"; do
  find "$icon_set" -maxdepth 1 -type f -name "*.png" -delete
done

while IFS=$'\t' read -r icon_set filename pixels; do
  output_path="$icon_set/$filename"
  "$MAGICK_BIN" "$SOURCE_IMAGE" \
    -auto-orient \
    -colorspace sRGB \
    -background "$BACKGROUND_COLOR" \
    -alpha remove \
    -alpha off \
    -filter Lanczos \
    -resize "${pixels}x${pixels}" \
    -gravity center \
    -extent "${pixels}x${pixels}" \
    -strip \
    -define png:compression-level=9 \
    "$output_path"

  if ! file "$output_path" | grep -q "PNG image data"; then
    echo "error: generated file is not a valid PNG: $output_path" >&2
    exit 1
  fi
done < "$manifest_file"

echo "Generated Pulsar app icons from: $SOURCE_IMAGE"
for icon_set in "${APP_ICON_SETS[@]}"; do
  count="$(find "$icon_set" -maxdepth 1 -type f -name "*.png" | wc -l | tr -d ' ')"
  echo "Updated $count PNG icons in: ${icon_set#$ROOT_DIR/}"
done
