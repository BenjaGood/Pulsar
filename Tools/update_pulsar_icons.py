#!/usr/bin/env python3

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
import shutil

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IOS_ICONSET = ROOT / "Pulsar/Assets.xcassets/AppIcon.appiconset"
WATCH_ICONSET = ROOT / "Pulsar Watch App Watch App/Assets.xcassets/AppIcon.appiconset"
MASTER_SOURCE = IOS_ICONSET / "icon_1024x1024@1x.png"
BACKUP_ROOT = ROOT / "build/icon-asset-backups"
GENERATED_ROOT = ROOT / "build/generated-icons"
SHARED_LOGOSET = ROOT / "Pulsar/Assets.xcassets/PulsarLogoRed.imageset"

RED_HEX = "#E11D48"
RED_RGB = (0xE1, 0x1D, 0x48)
SYMBOL_SCALE = 0.88


def derive_symbol_mask(source: Path) -> Image.Image:
    grayscale = np.array(Image.open(source).convert("L"))
    _, thresholded = cv2.threshold(grayscale, 0, 255, cv2.THRESH_BINARY)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    cleaned = cv2.morphologyEx(thresholded, cv2.MORPH_CLOSE, kernel, iterations=2)

    contours, _ = cv2.findContours(cleaned, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    mask = np.zeros_like(cleaned)
    cv2.drawContours(mask, contours, -1, 255, thickness=cv2.FILLED)

    return Image.fromarray(mask, mode="L")


def composite_master(mask: Image.Image, scale: float) -> Image.Image:
    canvas = Image.new("RGB", mask.size, RED_RGB)

    scaled_size = (
        max(1, round(mask.width * scale)),
        max(1, round(mask.height * scale)),
    )
    scaled_mask = mask.resize(scaled_size, Image.Resampling.LANCZOS)

    centered_mask = Image.new("L", mask.size, 0)
    x = (mask.width - scaled_size[0]) // 2
    y = (mask.height - scaled_size[1]) // 2
    centered_mask.paste(scaled_mask, (x, y))

    white_symbol = Image.new("RGB", mask.size, (255, 255, 255))
    canvas.paste(white_symbol, mask=centered_mask)
    return canvas


def ensure_backup(paths: list[Path]) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = BACKUP_ROOT / timestamp
    for path in paths:
        relative = path.relative_to(ROOT)
        destination = backup_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    return backup_dir


def render_to_size(master: Image.Image, size: tuple[int, int]) -> Image.Image:
    return master.resize(size, Image.Resampling.LANCZOS).convert("RGB")


def write_app_icons(master: Image.Image, icon_paths: list[Path]) -> list[tuple[Path, tuple[int, int]]]:
    results: list[tuple[Path, tuple[int, int]]] = []
    for icon_path in icon_paths:
        with Image.open(icon_path) as existing:
            size = existing.size
        rendered = render_to_size(master, size)
        rendered.save(icon_path, format="PNG", optimize=True)
        results.append((icon_path, size))
    return results


def ensure_shared_logo(master: Image.Image) -> Path:
    SHARED_LOGOSET.mkdir(parents=True, exist_ok=True)
    logo_path = SHARED_LOGOSET / "pulsar_logo_red.png"
    master.save(logo_path, format="PNG", optimize=True)

    contents = {
        "images": [{"filename": logo_path.name, "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
    }
    (SHARED_LOGOSET / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n",
        encoding="utf-8",
    )
    return logo_path


def main() -> None:
    icon_paths = sorted(IOS_ICONSET.glob("*.png")) + sorted(WATCH_ICONSET.glob("*.png"))
    backup_dir = ensure_backup(icon_paths)

    symbol_mask = derive_symbol_mask(MASTER_SOURCE)
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)
    symbol_mask.save(GENERATED_ROOT / "pulsar_symbol_mask.png", format="PNG", optimize=True)

    master = composite_master(symbol_mask, SYMBOL_SCALE)
    master_path = GENERATED_ROOT / "pulsar_red_master_1024.png"
    master.save(master_path, format="PNG", optimize=True)

    rendered_icons = write_app_icons(master, icon_paths)
    shared_logo = ensure_shared_logo(master)

    print(f"source_logo={MASTER_SOURCE}")
    print(f"backup_dir={backup_dir}")
    print(f"master_output={master_path}")
    print(f"shared_logo={shared_logo}")
    print(f"red={RED_HEX}")
    print(f"icon_count={len(rendered_icons)}")
    for icon_path, size in rendered_icons:
        print(f"{icon_path.relative_to(ROOT)}:{size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
