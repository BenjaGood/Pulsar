#!/usr/bin/env bash
set -euo pipefail

MARK_SOURCE="${1:-/Volumes/Benjamin SSD/Aetherial/Aetherial Main/Pulsar_2logo.png}"
WORDMARK_SOURCE="${2:-/Volumes/Benjamin SSD/Aetherial/Aetherial Main/PulsarComplete.png}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGICK_BIN="${MAGICK:-$(command -v magick || true)}"
BRAND_HEIGHT="${PULSAR_BRAND_ASSET_HEIGHT:-720}"
REGENERATE_APP_ICONS="${PULSAR_REGENERATE_APP_ICONS:-1}"

ASSET_CATALOGS=(
  "$ROOT_DIR/Pulsar/Assets.xcassets"
  "$ROOT_DIR/Pulsar Watch App Watch App/Assets.xcassets"
)

if [[ -z "$MAGICK_BIN" ]]; then
  echo "error: ImageMagick 'magick' was not found. Install it with Homebrew or set MAGICK=/path/to/magick." >&2
  exit 1
fi

if [[ ! -f "$MARK_SOURCE" ]]; then
  echo "error: P logo source not found: $MARK_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$WORDMARK_SOURCE" ]]; then
  echo "error: Pulsar wordmark source not found: $WORDMARK_SOURCE" >&2
  exit 1
fi

for catalog in "${ASSET_CATALOGS[@]}"; do
  if [[ ! -d "$catalog" ]]; then
    echo "error: asset catalog not found: $catalog" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

tail_crop="$(
python3 - "$WORDMARK_SOURCE" <<'PY'
from pathlib import Path
import sys

try:
    from PIL import Image
except Exception as error:
    raise SystemExit(f"error: Pillow is required to detect the wordmark tail crop: {error}")

image = Image.open(Path(sys.argv[1])).convert("RGBA")
width, height = image.size
alpha = image.getchannel("A")
threshold = 10

columns = []
for x in range(width):
    if alpha.crop((x, 0, x + 1, height)).getextrema()[1] > threshold:
        columns.append(x)

if not columns:
    raise SystemExit("error: wordmark source has no visible alpha content")

ranges = []
start = previous = columns[0]
for x in columns[1:]:
    if x > previous + 1:
        ranges.append((start, previous))
        start = x
    previous = x
ranges.append((start, previous))

bbox = image.getbbox()
if not bbox:
    raise SystemExit("error: wordmark source has no visible bounding box")

if len(ranges) >= 2:
    tail_x = ranges[0][1] + 1
else:
    tail_x = bbox[0] + int((bbox[2] - bbox[0]) * 0.32)

tail_y = bbox[1]
tail_w = bbox[2] - tail_x
tail_h = bbox[3] - bbox[1]

if tail_w <= 0 or tail_h <= 0:
    raise SystemExit(f"error: invalid tail crop {tail_w}x{tail_h}+{tail_x}+{tail_y}")

print(f"{tail_w}x{tail_h}+{tail_x}+{tail_y}")
PY
)"

make_dark_variant() {
  local input_path="$1"
  local output_path="$2"

  "$MAGICK_BIN" "$input_path" \
    -alpha set \
    -channel RGB \
    -fx '((r > (g * 1.22)) && (r > (b * 1.22)) && (r > 0.12)) ? u : 1' \
    +channel \
    -strip \
    "$output_path"
}

write_imageset() {
  local catalog="$1"
  local name="$2"
  local source_png="$3"
  local filename="${name}.png"
  local imageset="$catalog/${name}.imageset"

  mkdir -p "$imageset"
  find "$imageset" -maxdepth 1 -type f -name "*.png" -delete
  cp "$source_png" "$imageset/$filename"
  cat > "$imageset/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$filename",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

"$MAGICK_BIN" "$MARK_SOURCE" \
  -auto-orient \
  -alpha set \
  -trim +repage \
  -resize "x${BRAND_HEIGHT}" \
  -strip \
  "$tmp_dir/PulsarLogoLight.png"

make_dark_variant "$tmp_dir/PulsarLogoLight.png" "$tmp_dir/PulsarLogoDark.png"

"$MAGICK_BIN" "$WORDMARK_SOURCE" \
  -auto-orient \
  -alpha set \
  -trim +repage \
  -resize "x${BRAND_HEIGHT}" \
  -strip \
  "$tmp_dir/PulsarWordmarkLight.png"

make_dark_variant "$tmp_dir/PulsarWordmarkLight.png" "$tmp_dir/PulsarWordmarkDark.png"

"$MAGICK_BIN" "$WORDMARK_SOURCE" \
  -auto-orient \
  -alpha set \
  -crop "$tail_crop" +repage \
  -resize "x${BRAND_HEIGHT}" \
  -strip \
  "$tmp_dir/PulsarWordmarkTailLight.png"

make_dark_variant "$tmp_dir/PulsarWordmarkTailLight.png" "$tmp_dir/PulsarWordmarkTailDark.png"

for catalog in "${ASSET_CATALOGS[@]}"; do
  write_imageset "$catalog" "PulsarLogoLight" "$tmp_dir/PulsarLogoLight.png"
  write_imageset "$catalog" "PulsarLogoDark" "$tmp_dir/PulsarLogoDark.png"
  write_imageset "$catalog" "PulsarWordmarkLight" "$tmp_dir/PulsarWordmarkLight.png"
  write_imageset "$catalog" "PulsarWordmarkDark" "$tmp_dir/PulsarWordmarkDark.png"
  write_imageset "$catalog" "PulsarWordmarkTailLight" "$tmp_dir/PulsarWordmarkTailLight.png"
  write_imageset "$catalog" "PulsarWordmarkTailDark" "$tmp_dir/PulsarWordmarkTailDark.png"
done

if [[ "$REGENERATE_APP_ICONS" != "0" && -x "$ROOT_DIR/scripts/generate_app_icons.sh" ]]; then
  PULSAR_ICON_BACKGROUND="#FFFFFF" "$ROOT_DIR/scripts/generate_app_icons.sh" "$MARK_SOURCE"
fi

echo "Generated Pulsar brand assets from:"
echo "  P logo: $MARK_SOURCE"
echo "  Wordmark: $WORDMARK_SOURCE"
echo "  Tail crop: $tail_crop"
for catalog in "${ASSET_CATALOGS[@]}"; do
  echo "Updated launch logo imagesets in: ${catalog#$ROOT_DIR/}"
done
