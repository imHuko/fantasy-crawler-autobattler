from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GREEN = (0, 255, 0, 255)

SHEETS = [
    {
        "source": ROOT / "assets" / "icons" / "talents" / "talent_icons_sheet.png",
        "source_manifest": ROOT / "assets" / "icons" / "talents" / "talent_icons_sheet_manifest.json",
        "output": ROOT / "assets" / "icons" / "talents" / "talent_icons_sheet_green_bg.png",
        "manifest": ROOT / "assets" / "icons" / "talents" / "talent_icons_sheet_green_bg_manifest.json",
        "res_path": "res://assets/icons/talents/talent_icons_sheet_green_bg.png",
    },
    {
        "source": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_inventory_style_sheet.png",
        "source_manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_inventory_style_manifest.json",
        "output": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_inventory_style_green_bg.png",
        "manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_inventory_style_green_bg_manifest.json",
        "res_path": "res://assets/icons/action_skills/action_skill_icons_inventory_style_green_bg.png",
    },
    {
        "source": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sprite_style_sheet.png",
        "source_manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sprite_style_manifest.json",
        "output": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sprite_style_green_bg.png",
        "manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sprite_style_green_bg_manifest.json",
        "res_path": "res://assets/icons/action_skills/action_skill_icons_sprite_style_green_bg.png",
    },
    {
        "source": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sheet.png",
        "source_manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sheet_manifest.json",
        "output": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sheet_green_bg.png",
        "manifest": ROOT / "assets" / "icons" / "action_skills" / "action_skill_icons_sheet_green_bg_manifest.json",
        "res_path": "res://assets/icons/action_skills/action_skill_icons_sheet_green_bg.png",
    },
]


def is_existing_key_pixel(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    if a == 0:
        return True
    # Handles both exact magenta sheets and generated sheets whose key was
    # normalized close to magenta before this pass.
    return r >= 220 and g <= 40 and b >= 220


def make_green_sheet(config: dict) -> None:
    source = config["source"]
    if not source.exists():
        print(f"skip missing {source}")
        return

    image = Image.open(source).convert("RGBA")
    out = Image.new("RGBA", image.size, GREEN)
    src_pixels = image.load()
    out_pixels = out.load()

    for y in range(image.height):
        for x in range(image.width):
            pixel = src_pixels[x, y]
            if not is_existing_key_pixel(pixel):
                out_pixels[x, y] = pixel

    config["output"].parent.mkdir(parents=True, exist_ok=True)
    out.save(config["output"])

    manifest = json.loads(config["source_manifest"].read_text(encoding="utf-8"))
    manifest["sheet"] = config["res_path"]
    manifest["background"] = "#00FF00"
    manifest["background_rules"] = {
        "color": "#00FF00",
        "uniform": True,
        "no_gradient": True,
        "no_shadow": True,
        "no_glow_spill": True,
    }
    config["manifest"].write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(config["output"])
    print(config["manifest"])


def main() -> None:
    for sheet in SHEETS:
        make_green_sheet(sheet)


if __name__ == "__main__":
    main()
